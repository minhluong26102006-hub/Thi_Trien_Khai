const db = require('../config/db');
const { calculateDepreciation } = require('./assetController');

async function getKpiDashboard(req, res) {
  try {
    // 1. Total assets and count by status
    const statusResult = await db.query(`
      SELECT status, COUNT(*) AS count
      FROM assets
      GROUP BY status
    `);

    let totalAssets = 0;
    let availableCount = 0;
    let borrowedCount = 0;
    let maintenanceCount = 0;
    let retiredCount = 0;

    for (const row of statusResult.rows) {
      const cnt = parseInt(row.count, 10);
      totalAssets += cnt;
      if (row.status === 'available') availableCount = cnt;
      else if (row.status === 'borrowed') borrowedCount = cnt;
      else if (row.status === 'maintenance') maintenanceCount = cnt;
      else if (row.status === 'retired') retiredCount = cnt;
    }

    const borrowedRate = totalAssets > 0 ? ((borrowedCount / totalAssets) * 100).toFixed(1) : 0;

    // 2. Overdue loans count
    const overdueResult = await db.query(`
      SELECT COUNT(*) AS count
      FROM loans
      WHERE status = 'borrowed' AND due_date < CURRENT_DATE
    `);
    const overdueCount = parseInt(overdueResult.rows[0].count, 10);

    // 3. Total remaining depreciated value
    const allAssetsResult = await db.query(`
      SELECT purchase_price, purchase_date, useful_life_years, status
      FROM assets
      WHERE status != 'retired'
    `);

    let totalOriginalValue = 0;
    let totalRemainingValue = 0;

    for (const a of allAssetsResult.rows) {
      totalOriginalValue += Number(a.purchase_price);
      const dep = calculateDepreciation(a.purchase_price, a.purchase_date, a.useful_life_years);
      totalRemainingValue += dep.remainingValue;
    }

    // 4. Top borrowed assets
    const topBorrowedResult = await db.query(`
      SELECT a.asset_code, a.name, a.image_path, c.name AS category_name,
             COUNT(li.id) AS borrow_count
      FROM loan_items li
      JOIN assets a ON li.asset_id = a.id
      JOIN categories c ON a.category_id = c.id
      GROUP BY a.id, c.name
      ORDER BY borrow_count DESC
      LIMIT 5
    `);

    // 5. Monthly maintenance cost (last 6 months)
    const monthlyMaintenanceResult = await db.query(`
      SELECT TO_CHAR(started_at, 'MM/YYYY') AS month_label,
             SUM(cost) AS total_cost,
             COUNT(id) AS logs_count
      FROM maintenance_logs
      GROUP BY TO_CHAR(started_at, 'MM/YYYY'), TO_CHAR(started_at, 'YYYY-MM')
      ORDER BY TO_CHAR(started_at, 'YYYY-MM') DESC
      LIMIT 6
    `);

    // 6. Distribution by category
    const categoryDistResult = await db.query(`
      SELECT c.name, COUNT(a.id) AS asset_count
      FROM categories c
      LEFT JOIN assets a ON c.id = a.category_id
      GROUP BY c.id
      ORDER BY asset_count DESC
    `);

    res.render('kpi/dashboard', {
      title: 'Báo cáo chỉ số KPI & Khấu hao tài sản',
      kpi: {
        totalAssets,
        availableCount,
        borrowedCount,
        maintenanceCount,
        retiredCount,
        borrowedRate,
        overdueCount,
        totalOriginalValue,
        totalRemainingValue
      },
      topBorrowed: topBorrowedResult.rows,
      monthlyMaintenance: monthlyMaintenanceResult.rows,
      categoryDistribution: categoryDistResult.rows
    });
  } catch (err) {
    console.error('Error loading KPI dashboard:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tổng hợp báo cáo chỉ số KPI.'
    });
  }
}

module.exports = {
  getKpiDashboard
};