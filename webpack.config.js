public_path = require("path").resolve(__dirname+'/public')
module.exports = {
  context: public_path,
  entry: './app.js',

  output: {
    path: public_path,
    filename: "build.js"
  },

  module: {
    loaders: [
      {test: /\.css$/, loader: "style!css"}
    ]
  }
};
