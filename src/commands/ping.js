const { SlashCommandBuilder } = require("@discordjs/builders");
const axios = require("axios");

module.exports = {
  data: new SlashCommandBuilder()
    .setName("skin")
    .setDescription("Kafa veya vücut seçeneğiyle birlikte bir skin ismi belirtin.")
    .addStringOption(option =>
      option.setName("part")
        .setDescription("Seçenek: 'kafa' veya 'vücut'")
        .setRequired(true))
    .addStringOption(option =>
      option.setName("name")
        .setDescription("Oyuncu ismi")
        .setRequired(true)),
  run: async (client, interaction) => {
    const part = interaction.options.getString("part");
    const name = interaction.options.getString("name");

    if (part !== "kafa" && part !== "vücut") {
      return interaction.reply("Geçersiz seçenek. Lütfen 'kafa' veya 'vücut' seçeneğini belirtin.");
    }

    let url;
    if (part === "kafa") {
      url = `https://minotar.net/cube/${name}`;
    } else if (part === "vücut") {
      url = `https://minotar.net/body/${name}`;
    }

    // Minotar API'sine istek gönder
    try {
      const response = await axios.get(url, { responseType: "arraybuffer" });

      // Resmi Discord'a gönder
      await interaction.reply({
        content: `İşte ${part} için ${name}'in skin'i:`,
        files: [{ attachment: response.data, name: `${name}_${part}.png` }]
      });
    } catch (error) {
      console.error(error);
      return interaction.reply("Skin getirilemedi. Lütfen ismi doğru girdiğinizden emin olun.");
    }
  }
};
