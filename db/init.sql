-- ==============================================================================
-- Asset & Equipment Management System - Database Initialization Script
-- 7 Tables with Constraints, Foreign Keys, Indexes and Seed Data
-- ==============================================================================

SET client_encoding = 'UTF8';

-- 1. USERS
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    department VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('employee', 'manager', 'admin')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. CATEGORIES
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    sort_order INT DEFAULT 0
);

-- 3. LOCATIONS
CREATE TABLE IF NOT EXISTS locations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

-- 4. ASSETS
CREATE TABLE IF NOT EXISTS assets (
    id SERIAL PRIMARY KEY,
    asset_code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(200) NOT NULL,
    category_id INT NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
    location_id INT NOT NULL REFERENCES locations(id) ON DELETE RESTRICT,
    serial_number VARCHAR(100),
    purchase_date DATE NOT NULL,
    purchase_price NUMERIC(14,0) NOT NULL CHECK (purchase_price >= 0),
    useful_life_years INT NOT NULL CHECK (useful_life_years > 0),
    status VARCHAR(20) NOT NULL CHECK (status IN ('available', 'borrowed', 'maintenance', 'retired')),
    image_path VARCHAR(255),
    note TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. LOANS
CREATE TABLE IF NOT EXISTS loans (
    id SERIAL PRIMARY KEY,
    loan_code VARCHAR(50) UNIQUE NOT NULL,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'approved', 'borrowed', 'returned', 'rejected', 'cancelled')),
    purpose TEXT NOT NULL,
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    due_date DATE NOT NULL,
    approved_by INT REFERENCES users(id) ON DELETE SET NULL,
    borrowed_at TIMESTAMP WITH TIME ZONE,
    returned_at TIMESTAMP WITH TIME ZONE,
    received_by INT REFERENCES users(id) ON DELETE SET NULL,
    reject_reason TEXT
);

-- 6. LOAN ITEMS
CREATE TABLE IF NOT EXISTS loan_items (
    id SERIAL PRIMARY KEY,
    loan_id INT NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
    asset_id INT NOT NULL REFERENCES assets(id) ON DELETE RESTRICT,
    condition_out TEXT,
    condition_returned TEXT,
    UNIQUE(loan_id, asset_id)
);

-- 7. MAINTENANCE LOGS
CREATE TABLE IF NOT EXISTS maintenance_logs (
    id SERIAL PRIMARY KEY,
    asset_id INT NOT NULL REFERENCES assets(id) ON DELETE RESTRICT,
    type VARCHAR(20) NOT NULL CHECK (type IN ('repair', 'inspection', 'upgrade')),
    description TEXT NOT NULL,
    cost NUMERIC(12,0) NOT NULL CHECK (cost >= 0),
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMP WITH TIME ZONE,
    performed_by INT NOT NULL REFERENCES users(id) ON DELETE RESTRICT
);

-- INDEXES
CREATE INDEX IF NOT EXISTS idx_assets_category_id ON assets(category_id);
CREATE INDEX IF NOT EXISTS idx_assets_location_id ON assets(location_id);
CREATE INDEX IF NOT EXISTS idx_assets_status ON assets(status);
CREATE INDEX IF NOT EXISTS idx_assets_code ON assets(asset_code);

CREATE INDEX IF NOT EXISTS idx_loans_user_id ON loans(user_id);
CREATE INDEX IF NOT EXISTS idx_loans_status ON loans(status);
CREATE INDEX IF NOT EXISTS idx_loans_due_date ON loans(due_date);
CREATE INDEX IF NOT EXISTS idx_loans_code ON loans(loan_code);

CREATE INDEX IF NOT EXISTS idx_loan_items_loan_id ON loan_items(loan_id);
CREATE INDEX IF NOT EXISTS idx_loan_items_asset_id ON loan_items(asset_id);

CREATE INDEX IF NOT EXISTS idx_maintenance_logs_asset_id ON maintenance_logs(asset_id);

-- ==============================================================================
-- SEED DATA
-- ==============================================================================

-- Seed Users (Bcrypt hashed from node in container)
INSERT INTO users (id, username, email, password_hash, full_name, department, role, is_active) VALUES
(1, 'admin', 'admin@asset.local', '$2a$10$kCmWBDwK3ZEQIZtauKLAtO.h9YNCWuRWpJR93KEHMdzQGnE0D7MXi', 'Nguyễn Văn Quản Trị', 'Phòng CNTT & Quản trị Hệ thống', 'admin', true),
(2, 'thukho01', 'thukho01@asset.local', '$2a$10$Nrlx6rQlxa/2ozQitzm44uuUxzttLNbiFlibmyzWwXGA8oShbql2W', 'Trần Thị Thủ Kho', 'Phòng Quản lý Cơ sở Vật chất', 'manager', true),
(3, 'kythuat01', 'kythuat01@asset.local', '$2a$10$J5C/e3iELAWqiHB8AoTsT.DAg.lPR8utfjr71UpE5FhX99aYU9Frq', 'Lê Văn Kỹ Thuật', 'Đội Kỹ thuật & Bảo trì', 'manager', true),
(4, 'nhanvien01', 'nhanvien01@asset.local', '$2a$10$FFz7udlHMzs.kJ3OAjaoLOYypdIbjihS4lVquNU401v9Oa/HNh1jS', 'Phạm Văn Nhân Viên', 'Khoa Công nghệ Thông tin', 'employee', true),
(5, 'nhanvien02', 'nhanvien02@asset.local', '$2a$10$GsF.G6kze9GgXURluGJuDenU11jLA8wPWnaHN8FxuasTWirhSejIO', 'Hoàng Thị Nhân Viên', 'Phòng Đào tạo & Khảo thí', 'employee', true);

SELECT setval('users_id_seq', 5);

-- Seed Categories
INSERT INTO categories (id, name, sort_order) VALUES
(1, 'Laptop', 1),
(2, 'Máy chiếu', 2),
(3, 'Thiết bị mạng', 3),
(4, 'Màn hình', 4),
(5, 'Nội thất', 5),
(6, 'Dụng cụ', 6);

SELECT setval('categories_id_seq', 6);

-- Seed Locations
INSERT INTO locations (id, name, description) VALUES
(1, 'Kho chính', 'Kho lưu trữ trung tâm tầng trệt tòa A'),
(2, 'Phòng IT', 'Phòng kỹ thuật CNTT phòng 204 tòa B'),
(3, 'Phòng họp A', 'Phòng hội thảo lớn sức chứa 80 người'),
(4, 'Phòng họp B', 'Phòng họp giao ban chuyên môn tầng 3'),
(5, 'Phòng lab', 'Phòng thực hành máy tính và mạng lab 401'),
(6, 'Văn phòng', 'Khu làm việc mở cán bộ giảng viên');

SELECT setval('locations_id_seq', 6);

-- Seed Assets (26 items: available, borrowed, maintenance, retired)
INSERT INTO assets (id, asset_code, name, category_id, location_id, serial_number, purchase_date, purchase_price, useful_life_years, status, image_path, note) VALUES
-- 1-6: Laptop
(1, 'TS-LAP-001', 'Dell Latitude 5420 i5-1145G7/16GB/512GB', 1, 2, 'DL-5420-98214', '2023-03-15', 18500000, 3, 'available', '/images/assets/laptop.svg', 'Máy phục vụ công tác đào tạo và hội thảo'),
(2, 'TS-LAP-002', 'ThinkPad T14 Gen 2 Ryzen 7/16GB/512GB', 1, 6, 'TP-T14-11892', '2022-08-20', 22000000, 3, 'borrowed', '/images/assets/laptop.svg', 'Đang bàn giao cho cán bộ đi công tác'),
(3, 'TS-LAP-003', 'HP EliteBook 840 G8 i5/16GB/256GB', 1, 1, 'HP-840-77123', '2023-01-10', 19500000, 3, 'available', '/images/assets/laptop.svg', 'Máy dự phòng tại kho chính'),
(4, 'TS-LAP-004', 'MacBook Pro 14 M1 Pro/16GB/512GB', 1, 2, 'MB-M1P-44091', '2022-04-12', 35000000, 4, 'borrowed', '/images/assets/laptop.svg', 'Thiết bị đồ họa và multimedia'),
(5, 'TS-LAP-005', 'Asus ExpertBook B1 B1400 i3/8GB/256GB', 1, 2, 'AS-B14-55102', '2022-11-05', 14000000, 3, 'maintenance', '/images/assets/laptop.svg', 'Đang sửa chữa thay quạt tản nhiệt'),
(6, 'TS-LAP-006', 'Acer TravelMate P2 i3/4GB/500GB HDD', 1, 1, 'AC-TMP-00918', '2019-06-15', 12000000, 3, 'retired', '/images/assets/laptop.svg', 'Hết hạn khấu hao và hư hỏng bo mạch chủ'),

-- 7-10: Máy chiếu
(7, 'TS-MC-001', 'Máy chiếu Epson EB-X06 3600 ANSI Lumens', 2, 3, 'EP-X06-2291', '2023-02-18', 11500000, 5, 'available', '/images/assets/projector.svg', 'Thiết bị trình chiếu phòng họp A'),
(8, 'TS-MC-002', 'Máy chiếu Panasonic PT-LB386 3800 Lumens', 2, 4, 'PA-386-8812', '2022-09-10', 16800000, 5, 'borrowed', '/images/assets/projector.svg', 'Mượn phục vụ bảo vệ đồ án tốt nghiệp'),
(9, 'TS-MC-003', 'Máy chiếu Sony VPL-EX435 3200 Lumens', 2, 1, 'SO-435-6671', '2021-12-01', 14200000, 5, 'available', '/images/assets/projector.svg', 'Máy chiếu di động kèm vali chống sốc'),
(10, 'TS-MC-004', 'Máy chiếu BenQ MX550 3600 Lumens', 2, 1, 'BQ-550-1049', '2018-05-20', 9800000, 4, 'retired', '/images/assets/projector.svg', 'Cháy bóng đèn hình và già thấu kính'),

-- 11-14: Thiết bị mạng
(11, 'TS-NET-001', 'Switch Cisco Catalyst 2960-X 24 Port Gigabit', 3, 2, 'WS-C2960X-24TS', '2022-01-15', 18000000, 5, 'available', '/images/assets/network.svg', 'Switch mạng phòng IT lab'),
(12, 'TS-NET-002', 'Router MikroTik CCR1009-7G-1C-1S+ Cloud Core', 3, 2, 'MT-CCR1009-88', '2022-03-22', 12500000, 5, 'available', '/images/assets/network.svg', 'Router định tuyến trung tâm'),
(13, 'TS-NET-003', 'Access Point UniFi AP-AC-Pro Dual Band', 3, 1, 'UF-ACPRO-9921', '2023-05-10', 3400000, 4, 'available', '/images/assets/network.svg', 'Bộ phát Wi-Fi chuẩn doanh nghiệp'),
(14, 'TS-NET-004', 'Switch Aruba Instant On 1930 24G 4SFP/SFP+', 3, 5, 'AR-1930-3312', '2022-07-30', 7500000, 5, 'borrowed', '/images/assets/network.svg', 'Triển khai thử nghiệm tại phòng lab'),

-- 15-18: Màn hình
(15, 'TS-MH-001', 'Màn hình Dell UltraSharp U2422H 24 inch IPS', 4, 6, 'DL-U2422-991', '2023-04-10', 5800000, 4, 'available', '/images/assets/monitor.svg', 'Màn hình chuẩn màu đồ họa'),
(16, 'TS-MH-002', 'Màn hình LG 27QN600-B 27 inch 2K IPS 75Hz', 4, 2, 'LG-27QN-882', '2023-06-25', 6500000, 4, 'available', '/images/assets/monitor.svg', 'Màn hình hiển thị phòng điều hành'),
(17, 'TS-MH-003', 'Màn hình Samsung ViewFinity S6 27 inch QHD', 4, 5, 'SS-S627-771', '2022-10-14', 5200000, 4, 'borrowed', '/images/assets/monitor.svg', 'Mượn phục vụ nghiên cứu phòng lab'),
(18, 'TS-MH-004', 'Màn hình Asus ProArt PA248QV 24.1 inch 16:10', 4, 2, 'AS-PA248-12', '2023-08-01', 5900000, 4, 'maintenance', '/images/assets/monitor.svg', 'Lỗi nguồn adapter chập chờn'),

-- 19-22: Nội thất
(19, 'TS-NT-001', 'Bàn họp lớn gỗ sồi cao cấp 12 chỗ', 5, 3, 'BH-OAK-12C', '2021-05-15', 15000000, 8, 'available', '/images/assets/furniture.svg', 'Bàn họp chính hội trường A'),
(20, 'TS-NT-002', 'Ghế công thái học Ergonomic Sihoo M57', 5, 6, 'GH-SIHOO-57', '2023-02-20', 3800000, 5, 'available', '/images/assets/furniture.svg', 'Ghế làm việc cán bộ chuyên môn'),
(21, 'TS-NT-003', 'Tủ tài liệu chống cháy Hòa Phát 4 ngăn', 5, 1, 'TU-HP-CC4N', '2020-11-10', 6200000, 8, 'available', '/images/assets/furniture.svg', 'Lưu trữ hồ sơ tài sản'),
(22, 'TS-NT-004', 'Bàn làm việc chữ L chân sắt sơn tĩnh điện', 5, 6, 'BL-IRON-04', '2022-09-01', 2900000, 6, 'available', '/images/assets/furniture.svg', 'Bàn làm việc nhân viên văn phòng'),

-- 23-26: Dụng cụ
(23, 'TS-DC-001', 'Bộ máy khoan động lực Bosch GSB 550 550W', 6, 1, 'BO-GSB550-9', '2023-03-01', 1450000, 4, 'available', '/images/assets/tool.svg', 'Dụng cụ sửa chữa và lắp đặt cơ khí nhẹ'),
(24, 'TS-DC-002', 'Máy hàn cáp quang tự động Comway C6S', 6, 2, 'CW-C6S-8821', '2022-06-18', 28000000, 5, 'maintenance', '/images/assets/tool.svg', 'Đang hiệu chuẩn quang học và vệ sinh lưỡi dao'),
(25, 'TS-DC-003', 'Máy đo công suất quang Noyafa NF-8508', 6, 2, 'NF-8508-331', '2023-07-15', 1800000, 3, 'available', '/images/assets/tool.svg', 'Thiết bị đo kiểm tra cáp mạng và quang'),
(26, 'TS-DC-004', 'Bộ kìm bấm mạng đa năng Dintek RJ45/RJ11', 6, 1, 'DT-KBM-0012', '2023-09-10', 850000, 3, 'available', '/images/assets/tool.svg', 'Kìm bấm chuyên dụng thi công hệ thống');

SELECT setval('assets_id_seq', 26);

-- Seed Loans
-- Loan 1: Overdue borrowed loan (nhanvien01 borrowed TS-LAP-002, due 3 days ago)
INSERT INTO loans (id, loan_code, user_id, status, purpose, requested_at, due_date, approved_by, borrowed_at) VALUES
(1, 'LN-202410-001', 4, 'borrowed', 'Mượn laptop nghiên cứu và lập trình đề tài NCKH', CURRENT_TIMESTAMP - INTERVAL '15 days', CURRENT_DATE - INTERVAL '3 days', 2, CURRENT_TIMESTAMP - INTERVAL '14 days');

INSERT INTO loan_items (id, loan_id, asset_id, condition_out) VALUES
(1, 1, 2, 'Máy mới 95%, sạc pin đầy đủ');

-- Loan 2: Active borrowed loan (nhanvien02 borrowed TS-LAP-004 & TS-MC-002, due in 10 days)
INSERT INTO loans (id, loan_code, user_id, status, purpose, requested_at, due_date, approved_by, borrowed_at) VALUES
(2, 'LN-202410-002', 5, 'borrowed', 'Phục vụ thuyết trình báo cáo và bảo vệ đồ án', CURRENT_TIMESTAMP - INTERVAL '3 days', CURRENT_DATE + INTERVAL '10 days', 2, CURRENT_TIMESTAMP - INTERVAL '2 days');

INSERT INTO loan_items (id, loan_id, asset_id, condition_out) VALUES
(2, 2, 4, 'MacBook hoạt động hoàn hảo, bao đựng'),
(3, 2, 8, 'Máy chiếu Panasonic kèm dây cáp HDMI 10m');

-- Loan 3: Returned loan (nhanvien01 returned TS-NET-004)
INSERT INTO loans (id, loan_code, user_id, status, purpose, requested_at, due_date, approved_by, borrowed_at, returned_at, received_by) VALUES
(3, 'LN-202409-001', 4, 'returned', 'Cấu hình thử nghiệm mạng VLAN sinh viên', CURRENT_TIMESTAMP - INTERVAL '40 days', CURRENT_DATE - INTERVAL '20 days', 2, CURRENT_TIMESTAMP - INTERVAL '39 days', CURRENT_TIMESTAMP - INTERVAL '21 days', 3);

INSERT INTO loan_items (id, loan_id, asset_id, condition_out, condition_returned) VALUES
(4, 3, 14, 'Switch hoạt động bình thường', 'Trả đủ phụ kiện nguồn, hoạt động tốt');

-- Loan 4: Pending loan (nhanvien02 requested TS-LAP-001, awaiting approval)
INSERT INTO loans (id, loan_code, user_id, status, purpose, requested_at, due_date) VALUES
(4, 'LN-202410-003', 5, 'pending', 'Mượn laptop tham gia kỳ thi kỹ năng số sinh viên', CURRENT_TIMESTAMP - INTERVAL '1 hours', CURRENT_DATE + INTERVAL '7 days');

INSERT INTO loan_items (id, loan_id, asset_id, condition_out) VALUES
(5, 4, 1, 'Chưa bàn giao');

SELECT setval('loans_id_seq', 4);
SELECT setval('loan_items_id_seq', 5);

-- Seed Maintenance Logs
INSERT INTO maintenance_logs (id, asset_id, type, description, cost, started_at, finished_at, performed_by) VALUES
(1, 5, 'repair', 'Thay bàn phím và bảo dưỡng quạt tản nhiệt do phát tiếng ồn', 650000, CURRENT_TIMESTAMP - INTERVAL '5 days', NULL, 3),
(2, 24, 'inspection', 'Hiệu chuẩn định kỳ lưỡi dao cắt sợi quang và vệ sinh cảm biến quang', 1200000, CURRENT_TIMESTAMP - INTERVAL '2 days', NULL, 3),
(3, 1, 'upgrade', 'Nâng cấp thanh RAM từ 8GB lên 16GB Kingston DDR4', 850000, CURRENT_TIMESTAMP - INTERVAL '30 days', CURRENT_TIMESTAMP - INTERVAL '29 days', 3);

SELECT setval('maintenance_logs_id_seq', 3);
-- Prometheus postgres_exporter user
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'exporter') THEN
    CREATE ROLE exporter WITH LOGIN PASSWORD 'Exp_SecPass_2026_dbmon!';
  END IF;
  GRANT pg_monitor TO exporter;
  GRANT CONNECT ON DATABASE assetdb TO exporter;
END $$;
