-- 检查报告需要单独保存影像/检查所见，结论仍作为诊断结果保留。
ALTER TABLE exam_report
    ADD COLUMN finding_text TEXT NULL AFTER reported_by;

-- 门诊范围仅覆盖就诊历史及其检查报告，不引入挂号、处方和收费流程。
CREATE TABLE outpatient_visit (
    outpatient_visit_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    visit_no VARCHAR(32) NOT NULL UNIQUE,
    patient_id INT UNSIGNED NOT NULL,
    department_id INT UNSIGNED NULL,
    doctor_id INT UNSIGNED NULL,
    visited_at DATETIME NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'COMPLETED',
    clinical_note VARCHAR(500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_outpatient_visit_patient_time (patient_id, visited_at),
    CONSTRAINT fk_outpatient_visit_patient FOREIGN KEY (patient_id) REFERENCES patient(patient_id),
    CONSTRAINT fk_outpatient_visit_department FOREIGN KEY (department_id) REFERENCES department(department_id),
    CONSTRAINT fk_outpatient_visit_doctor FOREIGN KEY (doctor_id) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE outpatient_exam_order (
    outpatient_exam_order_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_no VARCHAR(32) NOT NULL UNIQUE,
    outpatient_visit_id INT UNSIGNED NOT NULL,
    doctor_id INT UNSIGNED NULL,
    ordered_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    priority VARCHAR(16) NOT NULL DEFAULT 'NORMAL',
    status VARCHAR(24) NOT NULL DEFAULT 'ORDERED',
    clinical_note VARCHAR(500) NULL,
    KEY idx_outpatient_exam_order_visit (outpatient_visit_id, ordered_at),
    CONSTRAINT fk_outpatient_exam_order_visit FOREIGN KEY (outpatient_visit_id)
        REFERENCES outpatient_visit(outpatient_visit_id),
    CONSTRAINT fk_outpatient_exam_order_doctor FOREIGN KEY (doctor_id) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE outpatient_exam_order_item (
    outpatient_exam_order_item_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    outpatient_exam_order_id INT UNSIGNED NOT NULL,
    exam_item_id INT UNSIGNED NOT NULL,
    execution_department_id INT UNSIGNED NULL,
    scheduled_at DATETIME NULL,
    executed_at DATETIME NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ORDERED',
    KEY idx_outpatient_exam_order_item_order (outpatient_exam_order_id),
    CONSTRAINT fk_outpatient_exam_order_item_order FOREIGN KEY (outpatient_exam_order_id)
        REFERENCES outpatient_exam_order(outpatient_exam_order_id),
    CONSTRAINT fk_outpatient_exam_order_item_exam FOREIGN KEY (exam_item_id) REFERENCES exam_item(exam_item_id),
    CONSTRAINT fk_outpatient_exam_order_item_department FOREIGN KEY (execution_department_id)
        REFERENCES department(department_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE outpatient_exam_report (
    outpatient_exam_report_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    outpatient_exam_order_item_id INT UNSIGNED NOT NULL UNIQUE,
    report_name VARCHAR(255) NOT NULL,
    reported_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reported_by INT UNSIGNED NULL,
    finding_text TEXT NULL,
    conclusion TEXT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'PUBLISHED',
    CONSTRAINT fk_outpatient_exam_report_item FOREIGN KEY (outpatient_exam_order_item_id)
        REFERENCES outpatient_exam_order_item(outpatient_exam_order_item_id),
    CONSTRAINT fk_outpatient_exam_report_user FOREIGN KEY (reported_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE outpatient_exam_result (
    outpatient_exam_result_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    outpatient_exam_report_id INT UNSIGNED NOT NULL,
    item_name VARCHAR(128) NOT NULL,
    qualitative_value VARCHAR(128) NULL,
    quantitative_value DECIMAL(12,4) NULL,
    unit VARCHAR(32) NULL,
    reference_range VARCHAR(128) NULL,
    abnormal_flag VARCHAR(16) NULL,
    remark VARCHAR(255) NULL,
    sort_no INT NOT NULL DEFAULT 1,
    KEY idx_outpatient_exam_result_report (outpatient_exam_report_id, sort_no),
    CONSTRAINT fk_outpatient_exam_result_report FOREIGN KEY (outpatient_exam_report_id)
        REFERENCES outpatient_exam_report(outpatient_exam_report_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
