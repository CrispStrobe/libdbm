/// Web-safe constants (JavaScript integer limits)
class DBMConstants {
  // Hash DBM Magic Number - Web-safe 56-bit
  static const int HASH_DBM_MAGIC = 0x1a7aba5eda7afee;
  
  // Hash Record Pool Header Magic Number - Web-safe 56-bit
  static const int HASH_RECORD_POOL_MAGIC = 0x0ba51c0da7aba5e;
  
  // Record Block Magic Number - Web-safe 56-bit
  static const int RECORD_BLOCK_MAGIC = 0x0c011ec7ed01eaf;
  
  // Memory Pool Header Magic Number - Web-safe 56-bit
  static const int MEMORY_POOL_MAGIC = 0x0c0a1e5ced0da7a;
  
  // Offset Mask - JavaScript MAX_SAFE_INTEGER (2^53 - 1)
  static const int OFFSET_MASK = 0x1fffffffffffff;
  
  // Length Mask - 32-bit, safe everywhere
  static const int LENGTH_MASK = 0x00000000ffffffff;
}
