const express = require('express');
const router = express.Router();

const { requireAuth, requireRole, checkGuest } = require('../middlewares/auth');
const { upload, validateMagicBytes } = require('../middlewares/upload');

const authController = require('../controllers/authController');
const assetController = require('../controllers/assetController');
const loanController = require('../controllers/loanController');
const maintenanceController = require('../controllers/maintenanceController');
const adminController = require('../controllers/adminController');
const kpiController = require('../controllers/kpiController');
const labelController = require('../controllers/labelController');

// 10. Healthcheck route (returns "OK")
router.get('/health', (req, res) => {
  res.status(200).send('OK');
});

// Root redirect
router.get('/', (req, res) => {
  if (req.session && req.session.user) {
    return res.redirect('/assets');
  }
  res.redirect('/auth/login');
});

// Auth Routes
router.get('/auth/login', checkGuest, authController.getLogin);
router.post('/auth/login', checkGuest, authController.postLogin);
router.get('/auth/register', checkGuest, authController.getRegister);
router.post('/auth/register', checkGuest, authController.postRegister);
router.get('/auth/logout', requireAuth, authController.logout);
router.post('/auth/logout', requireAuth, authController.logout);

// Assets Catalog & Detail (All logged in users)
router.get('/assets', requireAuth, assetController.getAssets);
router.get('/assets/:id', requireAuth, assetController.getAssetDetail);

// Asset Label & QR Code (Manager & Admin)
router.get('/assets/:id/label', requireAuth, requireRole(['manager', 'admin']), labelController.getAssetLabel);

// Loans Routes
router.get('/loans', requireAuth, loanController.getLoans);
router.get('/loans/create', requireAuth, loanController.getCreateLoan);
router.post('/loans/create', requireAuth, loanController.postCreateLoan);
router.get('/loans/overdue', requireAuth, requireRole(['manager', 'admin']), loanController.getOverdueLoans);
router.get('/loans/:id', requireAuth, loanController.getLoanDetail);
router.post('/loans/:id/cancel', requireAuth, loanController.postCancelLoan);

// Loan Processing (Manager & Admin)
router.post('/loans/:id/approve', requireAuth, requireRole(['manager', 'admin']), loanController.postApproveLoan);
router.post('/loans/:id/reject', requireAuth, requireRole(['manager', 'admin']), loanController.postRejectLoan);
router.post('/loans/:id/handover', requireAuth, requireRole(['manager', 'admin']), loanController.postHandoverLoan);
router.post('/loans/:id/return', requireAuth, requireRole(['manager', 'admin']), loanController.postReturnLoan);

// Maintenance Routes (Manager & Admin)
router.get('/maintenance', requireAuth, requireRole(['manager', 'admin']), maintenanceController.getMaintenanceList);
router.get('/maintenance/create', requireAuth, requireRole(['manager', 'admin']), maintenanceController.getCreateMaintenance);
router.post('/maintenance/create', requireAuth, requireRole(['manager', 'admin']), maintenanceController.postCreateMaintenance);
router.post('/maintenance/:id/finish', requireAuth, requireRole(['manager', 'admin']), maintenanceController.postFinishMaintenance);

// KPI Dashboard (Manager & Admin)
router.get('/kpi', requireAuth, requireRole(['manager', 'admin']), kpiController.getKpiDashboard);

// Admin-only Routes
router.get('/admin', requireAuth, requireRole(['admin']), adminController.getAdminIndex);

// Admin Asset CRUD & Retire
router.get('/admin/assets/new', requireAuth, requireRole(['admin']), adminController.getNewAssetForm);
router.post('/admin/assets/new', requireAuth, requireRole(['admin']), upload.single('image'), validateMagicBytes, adminController.postCreateAsset);
router.get('/admin/assets/:id/edit', requireAuth, requireRole(['admin']), adminController.getEditAssetForm);
router.post('/admin/assets/:id/edit', requireAuth, requireRole(['admin']), upload.single('image'), validateMagicBytes, adminController.postEditAsset);
router.post('/admin/assets/:id/retire', requireAuth, requireRole(['admin']), adminController.postRetireAsset);

// Admin Categories CRUD
router.get('/admin/categories', requireAuth, requireRole(['admin']), adminController.getCategories);
router.post('/admin/categories', requireAuth, requireRole(['admin']), adminController.postCreateCategory);

// Admin Locations CRUD
router.get('/admin/locations', requireAuth, requireRole(['admin']), adminController.getLocations);
router.post('/admin/locations', requireAuth, requireRole(['admin']), adminController.postCreateLocation);

// Admin Users Management
router.get('/admin/users', requireAuth, requireRole(['admin']), adminController.getUsers);
router.post('/admin/users', requireAuth, requireRole(['admin']), adminController.postCreateUser);
router.post('/admin/users/:id/toggle-active', requireAuth, requireRole(['admin']), adminController.postToggleUserActive);

module.exports = router;