const net = require('net');
const fs = require('fs').promises;
const crypto = require('crypto');
const { Webhook, MessageBuilder } = require('discord-webhook-node');

const webhookURL = process.env.webhook;
if (!webhookURL) throw new Error('DISCORD_WEBHOOK_URL environment variable not set!');
const webhook = new Webhook(webhookURL);

const TCP_PORT = 34953;
const MAX_CONNECTIONS_PER_IP = 2;
const MAX_TOTAL_CONNECTIONS = 100;
const MAX_MESSAGE_SIZE = 1024; // 1 KB
const SESSION_TIMEOUT_MS = 30 * 1000; // 30 saniye oturum boşta kalma süresi
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 dakika pencere
const MAX_REQUESTS_PER_WINDOW = 20; // 1 dakikada max 20 istek

// Aktif bağlantılar ve rate limit takibi
const activeConnections = new Map(); // ip -> Set of sockets
const rateLimits = new Map(); // ip -> [timestamp1, timestamp2, ...]

let totalConnections = 0;

// Discord uyarı fonksiyonu
async function sendDiscordAlert(message) {
  try {
    const embed = new MessageBuilder()
      .setTitle('Sunucu Güvenlik Bildirimi')
      .setColor('#FF0000')
      .setDescription(message)
      .setTimestamp();
    await webhook.send(embed);
  } catch (err) {
    console.error('Discord webhook gönderilemedi:', err);
  }
}

// Rate limiting kontrolü (IP bazlı)
function checkRateLimit(ip) {
  const now = Date.now();
  let timestamps = rateLimits.get(ip) || [];
  // Pencere dışı eski istekleri temizle
  timestamps = timestamps.filter(t => now - t < RATE_LIMIT_WINDOW_MS);
  if (timestamps.length >= MAX_REQUESTS_PER_WINDOW) return false;
  timestamps.push(now);
  rateLimits.set(ip, timestamps);
  return true;
}

// Mesaj format doğrulama
function validateMessage(data) {
  if (typeof data !== 'object') return false;
  const { key, hwid, version, pc, hash } = data;
  if (![key, hwid, version, pc, hash].every(f => typeof f === 'string')) return false;
  if (!/^[a-f0-9]{64}$/.test(hash)) return false; // SHA256 hex format
  return true;
}

// SHA256 hash hesaplama (client ile aynı mantıkta olmalı)
function calculateExpectedHash(key, hwid, version, pc) {
  return crypto.createHash('sha256').update(key + hwid + version + pc).digest('hex');
}

// Kullanıcı verilerini dosyadan oku
async function loadUsers() {
  try {
    const data = await fs.readFile('keys/users.json', 'utf8');
    return JSON.parse(data);
  } catch {
    return {};
  }
}

// Versiyon ve vdurum kontrolü
async function loadVersionInfo() {
  try {
    const data = await fs.readFile('keys/version.json', 'utf8');
    return JSON.parse(data);
  } catch {
    return { version: '0', vdurum: false };
  }
}

// HWID atama (sadece boşsa) ve dosyaya kaydetme
async function assignHWID(users, key, newHWID) {
  if (!users[key]) return false;
  if (users[key].hwid === '') {
    users[key].hwid = newHWID;
    await fs.writeFile('keys/users.json', JSON.stringify(users, null, 2));
    return true;
  }
  return false;
}

const server = net.createServer(async (socket) => {
  const ip = socket.remoteAddress;

  // Toplam ve IP bazlı bağlantı kontrolü
  if (totalConnections >= MAX_TOTAL_CONNECTIONS) {
    socket.write('maksbaglama');
    socket.end();
    return;
  }
  if (!activeConnections.has(ip)) activeConnections.set(ip, new Set());
  if (activeConnections.get(ip).size >= MAX_CONNECTIONS_PER_IP) {
    socket.write('maksbaglama');
    socket.end();
    return;
  }

  activeConnections.get(ip).add(socket);
  totalConnections++;

  let sessionTimeout = setTimeout(() => {
    socket.end();
  }, SESSION_TIMEOUT_MS);

  socket.setEncoding('utf8');

  socket.on('data', async (chunk) => {
    clearTimeout(sessionTimeout);
    sessionTimeout = setTimeout(() => socket.end(), SESSION_TIMEOUT_MS);

    if (chunk.length > MAX_MESSAGE_SIZE) {
      socket.write('msg_too_large');
      return;
    }

    let data;
    try {
      data = JSON.parse(chunk);
    } catch {
      socket.write('invalid_json');
      return;
    }

    if (!checkRateLimit(ip)) {
      socket.write('rate_limited');
      await sendDiscordAlert(`Rate limit aşıldı. IP: ${ip}`);
      return;
    }

    if (!validateMessage(data)) {
      socket.write('invalid_format');
      await sendDiscordAlert(`Geçersiz mesaj formatı. IP: ${ip} Mesaj: ${chunk.toString()}`);
      return;
    }

    const { key, hwid, version, pc, hash } = data;

    const users = await loadUsers();
    if (!users.hasOwnProperty(key)) {
      socket.write('notkey');
      await sendDiscordAlert(`Geçersiz key. IP: ${ip} Key: ${key}`);
      return;
    }

    // HWID sadece boşsa atanır, değiştirme yasak
    if (users[key].hwid === '') {
      const assigned = await assignHWID(users, key, hwid);
      if (!assigned) {
        socket.write('vdurum');
        await sendDiscordAlert(`HWID atanamadı. IP: ${ip}`);
        return;
      }
    } else if (users[key].hwid !== hwid) {
      socket.write('nothwid');
      await sendDiscordAlert(`HWID uyuşmazlığı. IP: ${ip}`);
      return;
    }

    const versionInfo = await loadVersionInfo();
    if (versionInfo.version !== version || !versionInfo.vdurum) {
      socket.write('notversion');
      await sendDiscordAlert(`Versiyon uyuşmazlığı veya sunucu kapalı. IP: ${ip}`);
      return;
    }

    // Süre kontrolü
    const now = new Date();
    const expireDate = new Date(users[key].exptime);
    if (now > expireDate) {
      socket.write('exptime');
      await sendDiscordAlert(`Lisans süresi dolmuş. IP: ${ip} Key: ${key}`);
      return;
    }

    // Hash kontrolü
    const expectedHash = calculateExpectedHash(key, hwid, version, pc);
    if (hash !== expectedHash) {
      socket.write('vdurum');
      await sendDiscordAlert(`Hash doğrulama başarısız. IP: ${ip}`);
      return;
    }

    // FreeKey kontrolü varsa hızlı erişim sağla
    if (users[key].freekey === 'true') {
      socket.write('authaccess');
      await sendDiscordAlert(`FreeKey ile giriş başarılı. IP: ${ip}`);
      return;
    }

    socket.write('authaccess');
    await sendDiscordAlert(`Giriş başarılı. IP: ${ip} Key: ${key}`);
  });

  socket.on('close', () => {
    clearTimeout(sessionTimeout);
    if (activeConnections.has(ip)) {
      activeConnections.get(ip).delete(socket);
      if (activeConnections.get(ip).size === 0) activeConnections.delete(ip);
    }
    totalConnections--;
  });

  socket.on('error', (err) => {
    clearTimeout(sessionTimeout);
    if (activeConnections.has(ip)) {
      activeConnections.get(ip).delete(socket);
      if (activeConnections.get(ip).size === 0) activeConnections.delete(ip);
    }
    totalConnections--;
    console.error('Socket error:', err);
  });
});

process.on('SIGINT', () => {
  console.log('Sunucu kapatılıyor...');
  server.close(() => {
    console.log('Sunucu kapandı.');
    process.exit(0);
  });
});

server.listen(TCP_PORT, () => {
  console.log(`TCP auth sunucusu ${TCP_PORT} portunda dinleniyor...`);
});
