const { ActivityType } = require("discord.js");
const { ip,mode,port } = require("../config.js");
const axios = require("axios");

module.exports = {
  name: "ready",
  once: true,
  execute(client) {
    console.log(`[DISCORD] ${client.user.tag} olarak giriş yapıldı`);

    setInterval(() => {
      axios.get(`https://api.mcstatus.io/v2/status/java/${ip}`)
        .then(response => {
          const data = response.data;

          if (mode === "aternos") {
            const motdLowerCase = data.motd.clean.toLowerCase();
            const isOffline = motdLowerCase.includes('this server is offline.');

            if (isOffline) {
              client.user.setActivity('Offline', { type: ActivityType.Playing });
            } else {
              const onlineStatus = data.online ? `Online [${data.players.online}/${data.players.max}]` : 'Offline';
              client.user.setActivity(`${onlineStatus}`, { type: ActivityType.Playing });
            }
          } else if (mode === "normal") {
            const onlineStatus = data.online ? `Şuanda ${data.players.online} Oyuncu Craftrise` : 'Offline';
            client.user.setActivity(`${onlineStatus}`, { type: ActivityType.Playing });
          } else {
            console.log(`[ERROR] Invalid "mode" value in config.json: ${mode}`);
          }
        })
        .catch(error => console.log(error));

      console.log('[İSTEK] İstek yapıldı');
    }, 20000);
  },
};
