const express = require('express');

const app = express();
const PORT = process.env.PORT || 3001;


const MESSAGE = 'Hot reload Node.js — version 2';

app.get('/', (req, res) => {
  res.send(`
    <html>
      <head><title>Stack Node.js</title></head>
      <body style="font-family: sans-serif; text-align: center; padding-top: 60px">
        <h1>${MESSAGE}</h1>
        <p>Servi par Express sur le port ${PORT}</p>
        <p>Demarre a ${new Date().toLocaleTimeString('fr-FR')}</p>
      </body>
    </html>
  `);
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Serveur demarre sur http://localhost:${PORT}`);
});
