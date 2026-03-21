const http = require('http');
let count = 0;
const server = http.createServer((req, res) => {
  if (req.url === '/increment') {
    count++;
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({count}));
  } else if (req.url === '/count') {
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({count}));
  } else {
    res.writeHead(200, {'Content-Type': 'text/html'});
    res.end('<html><body><h1>Counter App</h1><button onclick="fetch(\'/increment\').then(r=>r.json()).then(d=>document.getElementById(\'c\').textContent=d.count)">+1</button><p>Count: <span id="c">0</span></p></body></html>');
  }
});
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log('Server running on port ' + PORT));
