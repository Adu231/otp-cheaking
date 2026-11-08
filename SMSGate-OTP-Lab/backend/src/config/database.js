const mongoose = require('mongoose');
const dns = require('dns');

// Automatically configure public DNS servers to resolve MongoDB SRV records reliably
// Prevents querySrv ECONNREFUSED errors on Windows and ISP routers
try {
  dns.setServers(['8.8.8.8', '1.1.1.1']);
} catch (dnsError) {
  console.warn('[DATABASE] Could not set custom DNS servers:', dnsError.message);
}

const connectDatabase = async () => {
  const uri = process.env.MONGODB_URI;

  if (!uri) {
    console.warn(
      '\x1b[33m%s\x1b[0m',
      '[DATABASE WARNING] MONGODB_URI is not set in environment variables. Database features will be unavailable until configured.'
    );
    return;
  }

  try {
    const options = {
      serverSelectionTimeoutMS: 15000
    };

    // If MONGODB_URI does not contain an explicit database path, default to 'otp_checking'
    if (!uri.match(/mongodb(?:\+srv)?:\/\/[^\/]+\/([a-zA-Z0-9_\-]+)/)) {
      options.dbName = 'otp_checking';
    }

    const conn = await mongoose.connect(uri, options);
    console.log(`[DATABASE] MongoDB Connected: ${conn.connection.host} (Database: ${conn.connection.name})`);
  } catch (error) {
    console.error(`[DATABASE ERROR] Failed to connect to MongoDB: ${error.message}`);
    // Do not crash the entire process so users can inspect configuration
  }
};

mongoose.connection.on('disconnected', () => {
  console.warn('[DATABASE] MongoDB connection disconnected.');
});

mongoose.connection.on('error', (err) => {
  console.error(`[DATABASE ERROR] MongoDB runtime error: ${err.message}`);
});

module.exports = connectDatabase;

