import readline from 'readline';
import { decrypt } from './encryption';

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

rl.question('Enter the text for decryption: ', function (text) {
  rl.question('Password: ', function (password) {
    rl.close();
    console.log(decrypt(text, password));
  });
});
