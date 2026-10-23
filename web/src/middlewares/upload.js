const multer = require('multer');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const uploadDir = path.join(__dirname, '../../public/uploads');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    const uniqueName = `asset-${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
    cb(null, uniqueName);
  }
});

const fileFilter = (req, file, cb) => {
  const allowedExtensions = ['.png', '.jpg', '.jpeg', '.webp'];
  const allowedMimeTypes = ['image/png', 'image/jpeg', 'image/webp'];

  const ext = path.extname(file.originalname).toLowerCase();
  if (!allowedExtensions.includes(ext) || !allowedMimeTypes.includes(file.mimetype)) {
    return cb(new Error('Định dạng tệp không hợp lệ! Chỉ chấp nhận PNG, JPG, WEBP.'));
  }
  cb(null, true);
};

const upload = multer({
  storage,
  limits: { fileSize: 2 * 1024 * 1024 }, // 2 MB
  fileFilter
});

// Middleware to check magic bytes after upload
function validateMagicBytes(req, res, next) {
  if (!req.file) {
    return next();
  }

  const filePath = req.file.path;
  fs.open(filePath, 'r', (err, fd) => {
    if (err) {
      return next(err);
    }

    const buffer = Buffer.alloc(12);
    fs.read(fd, buffer, 0, 12, 0, (readErr) => {
      fs.close(fd, () => {});
      if (readErr) {
        fs.unlink(filePath, () => {});
        return res.status(400).render('partials/error', {
          title: 'Lỗi tải ảnh',
          statusCode: 400,
          message: 'Không thể đọc tệp ảnh đã tải lên.'
        });
      }

      // Check PNG: 89 50 4E 47
      const isPng = buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47;
      // Check JPEG: FF D8 FF
      const isJpeg = buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
      // Check WEBP: RIFF .... WEBP
      const isWebp = buffer.toString('ascii', 0, 4) === 'RIFF' && buffer.toString('ascii', 8, 12) === 'WEBP';

      if (!isPng && !isJpeg && !isWebp) {
        fs.unlink(filePath, () => {});
        return res.status(400).render('partials/error', {
          title: 'Tệp không hợp lệ',
          statusCode: 400,
          message: 'Tệp không phải là hình ảnh hợp lệ (Phát hiện magic bytes giả mạo hoặc tệp thực thi).'
        });
      }

      next();
    });
  });
}

module.exports = {
  upload,
  validateMagicBytes
};