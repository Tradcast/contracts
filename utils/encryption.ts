import crypto from 'crypto';

export function encrypt(text: string, key: string) {
  try {
    const cryptoKey = crypto.createHash('sha256').update(key).digest();
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv('aes-256-ctr', cryptoKey, iv);
    let encrypted = cipher.update(text);
    encrypted = Buffer.concat([encrypted, cipher.final()]);
    return iv.toString('hex') + ':' + encrypted.toString('hex');
  } catch (e) {
    console.log({ text, key });
    console.error(e);
    return '';
  }
}

export function decrypt(text: string, key: string) {
  try {
    const cryptoKey = crypto.createHash('sha256').update(key).digest();
    const textParts = text.split(':');
    const iv = Buffer.from(textParts.shift() || '', 'hex');
    const encryptedText = Buffer.from(textParts.join(':'), 'hex');
    const decipher = crypto.createDecipheriv('aes-256-ctr', cryptoKey, iv);
    let decrypted = decipher.update(encryptedText);
    decrypted = Buffer.concat([decrypted, decipher.final()]);
    return decrypted.toString();
  } catch (e) {
    console.log({ text, key });
    console.error(e);
    return '';
  }
}
