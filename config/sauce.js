var _ = require('lodash');
var os = require('os');

var options = {
  username: process.env.SAUCE_USER || 'voxmedia-quill',
  accessKey: process.env.SAUCE_KEY || 'd920e137-42a9-4b6a-8bc8-252c6808598f'
};

if (process.env.TRAVIS) {
  options.build = process.env.TRAVIS_BUILD_ID;
  options.tunnel = process.env.TRAVIS_JOB_NUMBER;
} else {
  var id = _.random(16*16*16*16).toString(16);
  options.build = os.hostname() + '-' + id;
  options.tunnel = os.hostname() + '-tunnel-' + id;
}

module.exports = options;
