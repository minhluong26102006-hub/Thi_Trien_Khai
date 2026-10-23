const QRCode = require('qrcode');
const db = require('../config/db');

async function getAssetLabel(req, res) {
  const { id } = req.params;

  try {
    const assetResult = await db.query(
      `SELECT a.*, c.name AS category_name, l.name AS location_name
       FROM assets a
       JOIN categories c ON a.category_id = c.id
       JOIN locations l ON a.location_id = l.id
       WHERE a.id = $1`,
      [id]
    );

    const asset = assetResult.rows[0];
    if (!asset) {
      return res.status(404).render('partials/error', {
        title: '404 Không tìm thấy',
        statusCode: 404,
        message: 'Tài sản không tồn tại!'
      });
    }

    // Server-side QR code generation containing asset metadata
    const qrPayload = JSON.stringify({
      code: asset.asset_code,
      name: asset.name,
      category: asset.category_name,
      location: asset.location_name,
      serial: asset.serial_number || 'N/A'
    });

    const qrDataUrl = await QRCode.toDataURL(qrPayload, {
      width: 220,
      margin: 1,
      errorCorrectionLevel: 'M',
      color: {
        dark: '#0f172a',
        light: '#ffffff'
      }
    });

    res.render('assets/label', {
      title: `Nhãn in tài sản - ${asset.asset_code}`,
      asset,
      qrDataUrl
    });
  } catch (err) {
    console.error('Error generating asset label:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tạo nhãn tài sản.'
    });
  }
}

module.exports = {
  getAssetLabel
};