module.exports = {
  singleQuote: true,
  arrowParens: 'always',
  bracketSpacing: true,
  printWidth: 100,
  trailingComma: 'es5', // can be "all"
  overrides: [
    {
      files: '*.sol',
      options: {
        printWidth: 100,
        tabWidth: 4,
        singleQuote: true,
        explicitTypes: 'always',
      },
    },
  ],
  plugins: [require.resolve('prettier-plugin-solidity')],
};
