export async function keypress() {
  process.stdin.setRawMode(true);
  return new Promise<void>((resolve) =>
    process.stdin.once('data', (data) => {
      if (data.length > 0 && data[0] === 3) {
        console.log('^C');
        process.exit(1);
      }
      process.stdin.setRawMode(false);
      resolve();
    })
  );
}

export default keypress;
