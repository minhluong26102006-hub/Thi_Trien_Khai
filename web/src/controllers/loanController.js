const crypto = require('crypto');
const db = require('../config/db');
const { logAssetStatusChange, logOverdueViewed } = require('../utils/logger');

function generateLoanCode() {
  const dateStr = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const randomSuffix = crypto.randomBytes(3).toString('hex').toUpperCase();
  return `LN-${dateStr}-${randomSuffix}`;
}

async function getLoans(req, res) {
  try {
    const user = req.session.user;
    const { status } = req.query;

    const conditions = [];
    const params = [];
    let paramIdx = 1;

    // Regular employee can only view their own loans
    if (user.role === 'employee') {
      conditions.push(`l.user_id = $${paramIdx}`);
      params.push(user.id);
      paramIdx++;
    }

    if (status) {
      conditions.push(`l.status = $${paramIdx}`);
      params.push(status);
      paramIdx++;
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const sql = `
      SELECT l.*, u.full_name AS borrower_name, u.department,
             COUNT(li.id) AS item_count,
             array_agg(a.asset_code || ' - ' || a.name) AS asset_titles
      FROM loans l
      JOIN users u ON l.user_id = u.id
      LEFT JOIN loan_items li ON l.id = li.loan_id
      LEFT JOIN assets a ON li.asset_id = a.id
      ${whereClause}
      GROUP BY l.id, u.id
      ORDER BY l.requested_at DESC
    `;

    const result = await db.query(sql, params);

    res.render('loans/index', {
      title: 'Quản lý phiếu mượn thiết bị',
      loans: result.rows,
      currentStatus: status || 'all'
    });
  } catch (err) {
    console.error('Error fetching loans:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải danh sách phiếu mượn.'
    });
  }
}

async function getCreateLoan(req, res) {
  try {
    const userId = req.session.user.id;

    // Check open loans count (max 3 open loans per user)
    const openLoansResult = await db.query(
      `SELECT id FROM loans WHERE user_id = $1 AND status IN ('pending', 'approved', 'borrowed')`,
      [userId]
    );

    if (openLoansResult.rows.length >= 3) {
      return res.status(400).render('partials/error', {
        title: 'Giới hạn mượn thiết bị',
        statusCode: 400,
        message: 'Bạn đang có 3 phiếu mượn chưa hoàn tất (đang chờ duyệt, đã duyệt hoặc đang mượn). Theo quy định, mỗi người dùng chỉ được mở tối đa 3 phiếu cùng lúc!'
      });
    }

    // Fetch available assets
    const assetsResult = await db.query(`
      SELECT a.*, c.name AS category_name, l.name AS location_name
      FROM assets a
      JOIN categories c ON a.category_id = c.id
      JOIN locations l ON a.location_id = l.id
      WHERE a.status = 'available'
      ORDER BY c.name ASC, a.name ASC
    `);

    // Min due date is tomorrow, max is 30 days from now
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const minDate = tomorrow.toISOString().split('T')[0];

    const maxDateObj = new Date();
    maxDateObj.setDate(maxDateObj.getDate() + 30);
    const maxDate = maxDateObj.toISOString().split('T')[0];

    res.render('loans/create', {
      title: 'Tạo phiếu mượn thiết bị',
      assets: assetsResult.rows,
      minDate,
      maxDate,
      error: null
    });
  } catch (err) {
    console.error('Error loading loan creation form:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải trang đăng ký mượn thiết bị.'
    });
  }
}

async function postCreateLoan(req, res) {
  const userId = req.session.user.id;
  let { asset_ids, purpose, due_date } = req.body;

  if (!asset_ids || !purpose || !due_date) {
    return res.status(400).render('partials/error', {
      title: 'Dữ liệu không hợp lệ',
      statusCode: 400,
      message: 'Vui lòng chọn thiết bị, nhập mục đích mượn và ngày hẹn trả!'
    });
  }

  if (!Array.isArray(asset_ids)) {
    asset_ids = [asset_ids];
  }

  // Validate: max 5 assets per loan
  if (asset_ids.length === 0 || asset_ids.length > 5) {
    return res.status(400).render('partials/error', {
      title: 'Giới hạn số lượng',
      statusCode: 400,
      message: 'Mỗi phiếu mượn được chọn tối thiểu 1 và tối đa 5 thiết bị!'
    });
  }

  // Validate due_date: within 30 days
  const now = new Date();
  const selectedDueDate = new Date(due_date);
  const maxDueDate = new Date();
  maxDueDate.setDate(maxDueDate.getDate() + 30);

  if (selectedDueDate <= now || selectedDueDate > maxDueDate) {
    return res.status(400).render('partials/error', {
      title: 'Ngày hẹn trả không hợp lệ',
      statusCode: 400,
      message: 'Thời hạn mượn phải từ 1 đến tối đa 30 ngày tính từ hôm nay!'
    });
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // Re-check open loans count with row lock
    const openLoans = await client.query(
      `SELECT id FROM loans WHERE user_id = $1 AND status IN ('pending', 'approved', 'borrowed') FOR UPDATE`,
      [userId]
    );
    if (openLoans.rows.length >= 3) {
      await client.query('ROLLBACK');
      return res.status(400).render('partials/error', {
        title: 'Giới hạn mượn thiết bị',
        statusCode: 400,
        message: 'Bạn đã đạt giới hạn 3 phiếu mượn đang mở!'
      });
    }

    // Verify all selected assets are currently available
    const assetsCheck = await client.query(
      `SELECT id, asset_code, status FROM assets WHERE id = ANY($1::int[]) FOR UPDATE`,
      [asset_ids.map(Number)]
    );

    if (assetsCheck.rows.length !== asset_ids.length) {
      await client.query('ROLLBACK');
      return res.status(400).render('partials/error', {
        title: 'Lỗi thiết bị',
        statusCode: 400,
        message: 'Một số thiết bị được chọn không tồn tại trong hệ thống!'
      });
    }

    for (const a of assetsCheck.rows) {
      if (a.status !== 'available') {
        await client.query('ROLLBACK');
        return res.status(400).render('partials/error', {
          title: 'Thiết bị không khả dụng',
          statusCode: 400,
          message: `Thiết bị [${a.asset_code}] hiện không ở trạng thái Sẵn sàng (Trạng thái hiện tại: ${a.status})!`
        });
      }
    }

    const loanCode = generateLoanCode();

    const insertLoan = await client.query(
      `INSERT INTO loans (loan_code, user_id, status, purpose, due_date)
       VALUES ($1, $2, 'pending', $3, $4)
       RETURNING id`,
      [loanCode, userId, purpose.trim(), due_date]
    );
    const loanId = insertLoan.rows[0].id;

    for (const aId of asset_ids) {
      await client.query(
        `INSERT INTO loan_items (loan_id, asset_id, condition_out)
         VALUES ($1, $2, 'Bình thường, sẵn sàng mượn')`,
        [loanId, parseInt(aId, 10)]
      );
    }

    await client.query('COMMIT');
    res.redirect('/loans');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error creating loan:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tạo phiếu mượn thiết bị. Vui lòng thử lại sau.'
    });
  } finally {
    client.release();
  }
}

async function getLoanDetail(req, res) {
  const { id } = req.params;
  const user = req.session.user;

  try {
    const loanResult = await db.query(
      `SELECT l.*, u.full_name AS borrower_name, u.email AS borrower_email, u.department AS borrower_department,
              ap.full_name AS approver_name, rc.full_name AS receiver_name
       FROM loans l
       JOIN users u ON l.user_id = u.id
       LEFT JOIN users ap ON l.approved_by = ap.id
       LEFT JOIN users rc ON l.received_by = rc.id
       WHERE l.id = $1`,
      [id]
    );

    const loan = loanResult.rows[0];
    if (!loan) {
      return res.status(404).render('partials/error', {
        title: '404 Không tìm thấy',
        statusCode: 404,
        message: 'Không tìm thấy phiếu mượn yêu cầu!'
      });
    }

    // Role check: Employee can only view their own loan
    if (user.role === 'employee' && loan.user_id !== user.id) {
      return res.status(403).render('partials/error', {
        title: '403 Cấm truy cập',
        statusCode: 403,
        message: 'Bạn không có quyền xem phiếu mượn của người khác!'
      });
    }

    const itemsResult = await db.query(
      `SELECT li.*, a.asset_code, a.name AS asset_name, a.status AS current_asset_status, a.image_path,
              c.name AS category_name, loc.name AS location_name
       FROM loan_items li
       JOIN assets a ON li.asset_id = a.id
       JOIN categories c ON a.category_id = c.id
       JOIN locations loc ON a.location_id = loc.id
       WHERE li.loan_id = $1`,
      [id]
    );

    res.render('loans/detail', {
      title: `Chi tiết phiếu mượn ${loan.loan_code}`,
      loan,
      items: itemsResult.rows
    });
  } catch (err) {
    console.error('Error fetching loan detail:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải chi tiết phiếu mượn.'
    });
  }
}

async function postCancelLoan(req, res) {
  const { id } = req.params;
  const user = req.session.user;

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const loanResult = await client.query('SELECT * FROM loans WHERE id = $1 FOR UPDATE', [id]);
    const loan = loanResult.rows[0];

    if (!loan) {
      await client.query('ROLLBACK');
      return res.status(404).render('partials/error', {
        title: '404 Không tìm thấy',
        statusCode: 404,
        message: 'Phiếu mượn không tồn tại!'
      });
    }

    // Check ownership if employee
    if (user.role === 'employee' && loan.user_id !== user.id) {
      await client.query('ROLLBACK');
      return res.status(403).render('partials/error', {
        title: '403 Cấm truy cập',
        statusCode: 403,
        message: 'Bạn chỉ có thể hủy phiếu mượn của chính mình!'
      });
    }

    // Only pending or approved loans can be cancelled
    if (loan.status !== 'pending' && loan.status !== 'approved') {
      await client.query('ROLLBACK');
      return res.status(400).render('partials/error', {
        title: 'Không thể hủy',
        statusCode: 400,
        message: 'Chỉ có thể hủy phiếu mượn đang ở trạng thái Chờ duyệt hoặc Đã duyệt!'
      });
    }

    await client.query(`UPDATE loans SET status = 'cancelled' WHERE id = $1`, [id]);
    await client.query('COMMIT');

    res.redirect(`/loans/${id}`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error cancelling loan:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể hủy phiếu mượn.'
    });
  } finally {
    client.release();
  }
}

async function postApproveLoan(req, res) {
  const { id } = req.params;
  const managerId = req.session.user.id;

  try {
    const result = await db.query(
      `UPDATE loans
       SET status = 'approved', approved_by = $1
       WHERE id = $2 AND status = 'pending'
       RETURNING id`,
      [managerId, id]
    );

    if (result.rows.length === 0) {
      return res.status(400).render('partials/error', {
        title: 'Không thể duyệt',
        statusCode: 400,
        message: 'Phiếu mượn không ở trạng thái Chờ duyệt!'
      });
    }

    res.redirect(`/loans/${id}`);
  } catch (err) {
    console.error('Error approving loan:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Có lỗi xảy ra khi duyệt phiếu mượn.'
    });
  }
}

async function postRejectLoan(req, res) {
  const { id } = req.params;
  const { reject_reason } = req.body;
  const managerId = req.session.user.id;

  try {
    const result = await db.query(
      `UPDATE loans
       SET status = 'rejected', reject_reason = $1, approved_by = $2
       WHERE id = $3 AND status = 'pending'
       RETURNING id`,
      [reject_reason || 'Không đủ điều kiện hoặc thiếu thiết bị', managerId, id]
    );

    if (result.rows.length === 0) {
      return res.status(400).render('partials/error', {
        title: 'Không thể từ chối',
        statusCode: 400,
        message: 'Phiếu mượn không ở trạng thái Chờ duyệt!'
      });
    }

    res.redirect(`/loans/${id}`);
  } catch (err) {
    console.error('Error rejecting loan:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Có lỗi xảy ra khi từ chối phiếu mượn.'
    });
  }
}

async function postHandoverLoan(req, res) {
  const { id } = req.params;
  const manager = req.session.user;

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // 1. Lock loan row
    const loanResult = await client.query('SELECT * FROM loans WHERE id = $1 FOR UPDATE', [id]);
    const loan = loanResult.rows[0];

    if (!loan || (loan.status !== 'approved' && loan.status !== 'pending')) {
      await client.query('ROLLBACK');
      return res.status(400).render('partials/error', {
        title: 'Không thể bàn giao',
        statusCode: 400,
        message: 'Phiếu mượn không ở trạng thái hợp lệ để bàn giao thiết bị!'
      });
    }

    // 2. Fetch loan items
    const itemsResult = await client.query(
      'SELECT asset_id FROM loan_items WHERE loan_id = $1',
      [id]
    );
    const assetIds = itemsResult.rows.map(r => r.asset_id);

    // 3. Concurrency check: SELECT ... FOR UPDATE on assets
    const assetsLock = await client.query(
      `SELECT id, asset_code, status FROM assets WHERE id = ANY($1::int[]) FOR UPDATE`,
      [assetIds]
    );

    // Check if any asset is NOT available
    for (const asset of assetsLock.rows) {
      if (asset.status !== 'available') {
        await client.query('ROLLBACK');
        return res.status(409).render('partials/error', {
          title: 'Xung đột cấp phát',
          statusCode: 409,
          message: `Không thể bàn giao: Thiết bị [${asset.asset_code}] hiện đang ở trạng thái "${asset.status}" (không phải available)!`
        });
      }
    }

    // 4. Update assets to 'borrowed' and log each
    for (const asset of assetsLock.rows) {
      await client.query(`UPDATE assets SET status = 'borrowed' WHERE id = $1`, [asset.id]);
      logAssetStatusChange(asset.asset_code, 'available', 'borrowed', manager.username);
    }

    // 5. Update loan status to 'borrowed'
    await client.query(
      `UPDATE loans
       SET status = 'borrowed', borrowed_at = CURRENT_TIMESTAMP, approved_by = COALESCE(approved_by, $1)
       WHERE id = $2`,
      [manager.id, id]
    );

    await client.query('COMMIT');
    res.redirect(`/loans/${id}`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error during handover:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Có lỗi xảy ra trong quá trình bàn giao thiết bị.'
    });
  } finally {
    client.release();
  }
}

async function postReturnLoan(req, res) {
  const { id } = req.params;
  const manager = req.session.user;
  const { conditions, damaged_assets } = req.body;

  const damagedIds = Array.isArray(damaged_assets)
    ? damaged_assets.map(Number)
    : damaged_assets ? [Number(damaged_assets)] : [];

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // Lock loan row
    const loanResult = await client.query('SELECT * FROM loans WHERE id = $1 FOR UPDATE', [id]);
    const loan = loanResult.rows[0];

    if (!loan || loan.status !== 'borrowed') {
      await client.query('ROLLBACK');
      return res.status(400).render('partials/error', {
        title: 'Không thể nhận trả',
        statusCode: 400,
        message: 'Phiếu mượn không ở trạng thái Đang mượn!'
      });
    }

    // Fetch loan items
    const itemsResult = await client.query(
      'SELECT id, asset_id FROM loan_items WHERE loan_id = $1',
      [id]
    );

    const assetIds = itemsResult.rows.map(r => r.asset_id);
    const assetsLock = await client.query(
      `SELECT id, asset_code, status FROM assets WHERE id = ANY($1::int[]) FOR UPDATE`,
      [assetIds]
    );

    for (const asset of assetsLock.rows) {
      const returnCond = (conditions && conditions[asset.id]) ? conditions[asset.id].trim() : 'Bình thường khi nhận lại';
      const isDamaged = damagedIds.includes(asset.id) ||
                        /hỏng|hư|lỗi|vỡ|hỏng hóc|damaged|broken/i.test(returnCond);

      // Update condition_returned in loan_items
      await client.query(
        `UPDATE loan_items SET condition_returned = $1 WHERE loan_id = $2 AND asset_id = $3`,
        [returnCond, id, asset.id]
      );

      if (isDamaged) {
        // Move asset to maintenance
        await client.query(`UPDATE assets SET status = 'maintenance' WHERE id = $1`, [asset.id]);
        logAssetStatusChange(asset.asset_code, 'borrowed', 'maintenance', manager.username);

        // Create initial maintenance log
        await client.query(
          `INSERT INTO maintenance_logs (asset_id, type, description, cost, started_at, performed_by)
           VALUES ($1, 'repair', $2, 0, CURRENT_TIMESTAMP, $3)`,
          [asset.id, `Ghi nhận hư hỏng khi nhận trả từ phiếu ${loan.loan_code}: ${returnCond}`, manager.id]
        );
      } else {
        // Return asset to available
        await client.query(`UPDATE assets SET status = 'available' WHERE id = $1`, [asset.id]);
        logAssetStatusChange(asset.asset_code, 'borrowed', 'available', manager.username);
      }
    }

    // Update loan to returned
    await client.query(
      `UPDATE loans
       SET status = 'returned', returned_at = CURRENT_TIMESTAMP, received_by = $1
       WHERE id = $2`,
      [manager.id, id]
    );

    await client.query('COMMIT');
    res.redirect(`/loans/${id}`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error during return processing:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Có lỗi xảy ra trong quá trình nhận trả thiết bị.'
    });
  } finally {
    client.release();
  }
}

async function getOverdueLoans(req, res) {
  try {
    const user = req.session.user;

    const sql = `
      SELECT l.*, u.full_name AS borrower_name, u.email AS borrower_email, u.department,
             (CURRENT_DATE - l.due_date) AS days_overdue,
             array_agg(a.asset_code || ' - ' || a.name) AS asset_titles
      FROM loans l
      JOIN users u ON l.user_id = u.id
      JOIN loan_items li ON l.id = li.loan_id
      JOIN assets a ON li.asset_id = a.id
      WHERE l.status = 'borrowed' AND l.due_date < CURRENT_DATE
      GROUP BY l.id, u.id
      ORDER BY days_overdue DESC
    `;

    const result = await db.query(sql);

    // Requirement: log LOAN_OVERDUE_VIEWED count=<n> by=<username>
    logOverdueViewed(result.rows.length, user.username);

    res.render('loans/overdue', {
      title: 'Danh sách phiếu mượn quá hạn',
      loans: result.rows
    });
  } catch (err) {
    console.error('Error fetching overdue loans:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải danh sách phiếu quá hạn.'
    });
  }
}

module.exports = {
  getLoans,
  getCreateLoan,
  postCreateLoan,
  getLoanDetail,
  postCancelLoan,
  postApproveLoan,
  postRejectLoan,
  postHandoverLoan,
  postReturnLoan,
  getOverdueLoans
};