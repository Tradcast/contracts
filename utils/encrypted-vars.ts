import { encrypt, decrypt } from './encryption';
import crypto from 'crypto';
import os from 'os';
import path from 'path';
import fs from 'fs';
import promptSync from 'prompt-sync';

const prompt = promptSync({});

export function decryptVars(obj: { [key: string]: string | undefined }) {
  const encryptedKeys = Object.keys(obj).filter((key) => key.startsWith('ENCRYPTED_'));
  const firstKey = encryptedKeys.find((key) => !!obj[key]);
  if (!firstKey) {
    return;
  }
  const firstValue = obj[firstKey] || '';

  if (encryptedKeys.length > 0) {
    const fileKey = generateFileKey(); // hash1
    const fileName = sha256hex(fileKey); // hash2
    const filePath = path.join(os.tmpdir(), fileName + '.txt');

    let password = null;

    if (fs.existsSync(filePath)) {
      const fileContent = decrypt(fs.readFileSync(filePath, 'utf8'), fileKey);
      if (fileContent.startsWith('envpass:')) {
        password = fileContent.substring('envpass:'.length);
        const firstDecrypted = decrypt(firstValue, password);
        if (firstDecrypted.startsWith('envval:') === false) {
          password = null;
        }
      }
    }

    if (password == null) {
      while (password == null) {
        const tPass: string = prompt('Enter password to decrypt variables:', { echo: '*' });
        if (tPass) {
          const firstDecrypted = decrypt(firstValue, tPass);
          if (firstDecrypted.startsWith('envval:')) {
            password = tPass;
          } else {
            console.log('Incorrect password');
          }
        }
      }

      fs.writeFileSync(filePath, encrypt('envpass:' + password, fileKey));
    }

    for (const key of encryptedKeys) {
      const val = obj[key];
      if (val) {
        const newKey = key.substring('ENCRYPTED_'.length);
        const decrypted = decrypt(val, password);
        obj[newKey] = decrypted.substring('envval:'.length);
      }
    }
  }
}

function generateFileKey() {
  const keys = [
    'SHELL',
    'SESSION_MANAGER',
    'WINDOWID',
    'XDG_SESSION_PATH',
    'PWD',
    'XDG_SESSION_ID',
    'XDG_RUNTIME_DIR',
    'DBUS_SESSION_BUS_ADDRESS',
    'TERM_PROGRAM',
    'TERM_SESSION_ID',
    'TEMP',
    'SESSIONNAME',
    'USERNAME',
    'SSH_CLIENT',
    'SSH_CONNECTION',
  ];
  const envVars = keys.map((key) => key + '=' + (process.env[key] || '')).join(',');
  // process ppid can be added
  const info = `encrypted-vars:${process.cwd()} ${envVars} ${process.getuid()} ${process.getgid()}`;
  return sha256hex(info);
}

function sha256hex(text: string) {
  return crypto.createHash('sha256').update(text).digest('hex');
}
