import readline from 'readline';
import { encrypt } from './encryption';

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

rl.question('Enter the text for encryption: ', function (text) {
  rl.question('Password: ', function (password) {
    rl.close();
    console.log(encrypt('envval:' + text, password));
  });
});
