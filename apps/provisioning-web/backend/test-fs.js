const fs = require('fs');
console.log('fs module:', typeof fs);
console.log('fs.existsSync:', typeof fs.existsSync);
console.log('Testing fs.existsSync:', fs.existsSync(__filename));