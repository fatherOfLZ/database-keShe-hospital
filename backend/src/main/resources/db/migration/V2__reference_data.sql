INSERT INTO role (role_code, role_name, description) VALUES
('SUPER_ADMIN', '最高管理员', '维护基础资料、账号及全院统计'),
('ADMISSION', '住院处', '办理入院、床位、押金、转科和结算'),
('DOCTOR', '医师', '维护病历、诊断和医嘱');

INSERT INTO department (department_code, department_name, department_type, phone) VALUES
('ADM', '住院处', 'ADMIN', '0532-00000001'),
('NEU', '神经内科', 'CLINICAL', '0532-00000002'),
('LAB', '检验科', 'TECHNICAL', '0532-00000003'),
('RAD', '放射科', 'TECHNICAL', '0532-00000004');

INSERT INTO ward (department_id, ward_code, ward_name, floor_no) VALUES
((SELECT department_id FROM department WHERE department_code='NEU'), 'NEU-A', '神经内科一病区', '5F'),
((SELECT department_id FROM department WHERE department_code='NEU'), 'NEU-B', '神经内科二病区', '6F');

INSERT INTO bed (ward_id, bed_no, bed_type, nursing_level) VALUES
((SELECT ward_id FROM ward WHERE ward_code='NEU-A'), '501', 'GENERAL', 'LEVEL_3'),
((SELECT ward_id FROM ward WHERE ward_code='NEU-A'), '502', 'GENERAL', 'LEVEL_3'),
((SELECT ward_id FROM ward WHERE ward_code='NEU-A'), '503', 'ICU', 'LEVEL_1'),
((SELECT ward_id FROM ward WHERE ward_code='NEU-B'), '601', 'GENERAL', 'LEVEL_2'),
((SELECT ward_id FROM ward WHERE ward_code='NEU-B'), '602', 'GENERAL', 'LEVEL_2');

INSERT INTO drug (drug_code, drug_name, generic_name, specification, dosage_form, unit, unit_price, stock_qty) VALUES
('D001', '阿司匹林肠溶片', '阿司匹林', '100mg*30片', '片剂', '盒', 18.50, 300),
('D002', '阿托伐他汀钙片', '阿托伐他汀钙', '20mg*7片', '片剂', '盒', 36.80, 200),
('D003', '氯化钠注射液', '氯化钠', '500ml', '注射液', '瓶', 6.20, 500);

INSERT INTO exam_item (item_code, item_name, item_type, department_id, unit, reference_range, unit_price) VALUES
('E001', '血常规', 'LAB', (SELECT department_id FROM department WHERE department_code='LAB'), NULL, NULL, 28.00),
('E002', '肝肾功能', 'LAB', (SELECT department_id FROM department WHERE department_code='LAB'), NULL, NULL, 48.00),
('E003', '头颅CT', 'EXAM', (SELECT department_id FROM department WHERE department_code='RAD'), NULL, NULL, 260.00);
