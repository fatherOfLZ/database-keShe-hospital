CREATE TABLE role (
    role_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    role_code VARCHAR(32) NOT NULL UNIQUE,
    role_name VARCHAR(64) NOT NULL,
    description VARCHAR(255),
    is_active BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE department (
    department_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    department_code VARCHAR(32) NOT NULL UNIQUE,
    department_name VARCHAR(100) NOT NULL UNIQUE,
    department_type VARCHAR(32) NOT NULL,
    phone VARCHAR(32),
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE system_user (
    user_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    role_id INT UNSIGNED NOT NULL,
    department_id INT UNSIGNED NULL,
    username VARCHAR(64) NOT NULL UNIQUE,
    password_hash VARCHAR(100) NOT NULL,
    real_name VARCHAR(64) NOT NULL,
    employee_no VARCHAR(32) UNIQUE,
    license_no VARCHAR(64) UNIQUE,
    phone VARCHAR(32),
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_user_role FOREIGN KEY (role_id) REFERENCES role(role_id),
    CONSTRAINT fk_user_department FOREIGN KEY (department_id) REFERENCES department(department_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE ward (
    ward_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    department_id INT UNSIGNED NOT NULL,
    ward_code VARCHAR(32) NOT NULL UNIQUE,
    ward_name VARCHAR(100) NOT NULL,
    floor_no VARCHAR(16),
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT fk_ward_department FOREIGN KEY (department_id) REFERENCES department(department_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE bed (
    bed_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ward_id INT UNSIGNED NOT NULL,
    bed_no VARCHAR(16) NOT NULL,
    bed_type VARCHAR(32) NOT NULL DEFAULT 'GENERAL',
    nursing_level VARCHAR(16) NOT NULL DEFAULT 'LEVEL_3',
    status VARCHAR(16) NOT NULL DEFAULT 'AVAILABLE',
    UNIQUE KEY uk_bed_ward_no (ward_id, bed_no),
    CONSTRAINT fk_bed_ward FOREIGN KEY (ward_id) REFERENCES ward(ward_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE patient (
    patient_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    patient_no VARCHAR(32) NOT NULL UNIQUE,
    name VARCHAR(64) NOT NULL,
    id_card_no VARCHAR(32) UNIQUE,
    gender VARCHAR(8) NOT NULL,
    birth_date DATE NOT NULL,
    height_cm DECIMAL(5,2),
    weight_kg DECIMAL(5,2),
    phone VARCHAR(32),
    ethnicity VARCHAR(32),
    marital_status VARCHAR(16),
    birth_place VARCHAR(255),
    address VARCHAR(255),
    emergency_contact_name VARCHAR(64),
    emergency_contact_phone VARCHAR(32),
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE patient_allergy (
    allergy_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    patient_id INT UNSIGNED NOT NULL,
    allergen_name VARCHAR(100) NOT NULL,
    allergy_type VARCHAR(16) NOT NULL,
    result VARCHAR(16) NOT NULL,
    reaction_text VARCHAR(255),
    severity VARCHAR(16),
    recorded_by INT UNSIGNED NOT NULL,
    recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    remark VARCHAR(255),
    CONSTRAINT fk_allergy_patient FOREIGN KEY (patient_id) REFERENCES patient(patient_id),
    CONSTRAINT fk_allergy_user FOREIGN KEY (recorded_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE drug (
    drug_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    drug_code VARCHAR(32) NOT NULL UNIQUE,
    drug_name VARCHAR(128) NOT NULL,
    generic_name VARCHAR(128),
    specification VARCHAR(128),
    dosage_form VARCHAR(32),
    unit VARCHAR(16) NOT NULL,
    insurance_code VARCHAR(64),
    unit_price DECIMAL(10,2) NOT NULL,
    stock_qty INT NOT NULL DEFAULT 0,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE exam_item (
    exam_item_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    item_code VARCHAR(32) NOT NULL UNIQUE,
    item_name VARCHAR(128) NOT NULL,
    item_type VARCHAR(16) NOT NULL,
    department_id INT UNSIGNED NULL,
    unit VARCHAR(32),
    reference_range VARCHAR(128),
    unit_price DECIMAL(10,2) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT fk_exam_item_department FOREIGN KEY (department_id) REFERENCES department(department_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE admission (
    admission_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    patient_id INT UNSIGNED NOT NULL,
    inpatient_no VARCHAR(32) NOT NULL UNIQUE,
    medical_record_no VARCHAR(32) NOT NULL UNIQUE,
    admitting_department_id INT UNSIGNED NOT NULL,
    current_department_id INT UNSIGNED NOT NULL,
    attending_doctor_id INT UNSIGNED NULL,
    current_bed_id INT UNSIGNED NULL,
    admission_time DATETIME NOT NULL,
    discharge_time DATETIME NULL,
    nursing_level VARCHAR(16) NOT NULL DEFAULT 'LEVEL_3',
    fee_type VARCHAR(32) NOT NULL DEFAULT 'SELF_PAY',
    insurance_type VARCHAR(64),
    status VARCHAR(16) NOT NULL DEFAULT 'IN_HOSPITAL',
    created_by INT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_admission_patient (patient_id),
    KEY idx_admission_status_dept (status, current_department_id),
    CONSTRAINT fk_admission_patient FOREIGN KEY (patient_id) REFERENCES patient(patient_id),
    CONSTRAINT fk_admission_admitting_dept FOREIGN KEY (admitting_department_id) REFERENCES department(department_id),
    CONSTRAINT fk_admission_current_dept FOREIGN KEY (current_department_id) REFERENCES department(department_id),
    CONSTRAINT fk_admission_doctor FOREIGN KEY (attending_doctor_id) REFERENCES system_user(user_id),
    CONSTRAINT fk_admission_bed FOREIGN KEY (current_bed_id) REFERENCES bed(bed_id),
    CONSTRAINT fk_admission_creator FOREIGN KEY (created_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE department_transfer (
    transfer_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    from_department_id INT UNSIGNED NOT NULL,
    to_department_id INT UNSIGNED NOT NULL,
    from_bed_id INT UNSIGNED NULL,
    to_bed_id INT UNSIGNED NULL,
    requested_by INT UNSIGNED NOT NULL,
    approved_by INT UNSIGNED NULL,
    request_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_time DATETIME NULL,
    reason VARCHAR(500) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    CONSTRAINT fk_transfer_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_transfer_from_dept FOREIGN KEY (from_department_id) REFERENCES department(department_id),
    CONSTRAINT fk_transfer_to_dept FOREIGN KEY (to_department_id) REFERENCES department(department_id),
    CONSTRAINT fk_transfer_from_bed FOREIGN KEY (from_bed_id) REFERENCES bed(bed_id),
    CONSTRAINT fk_transfer_to_bed FOREIGN KEY (to_bed_id) REFERENCES bed(bed_id),
    CONSTRAINT fk_transfer_requester FOREIGN KEY (requested_by) REFERENCES system_user(user_id),
    CONSTRAINT fk_transfer_approver FOREIGN KEY (approved_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE diagnosis (
    diagnosis_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    diagnosis_code VARCHAR(32),
    diagnosis_name VARCHAR(255) NOT NULL,
    diagnosis_type VARCHAR(16) NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    diagnosed_by INT UNSIGNED NOT NULL,
    diagnosed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT fk_diagnosis_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_diagnosis_doctor FOREIGN KEY (diagnosed_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE medical_record (
    record_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    record_type VARCHAR(32) NOT NULL,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    recorded_by INT UNSIGNED NOT NULL,
    recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    signed_at DATETIME NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'DRAFT',
    version_no INT NOT NULL DEFAULT 1,
    CONSTRAINT fk_record_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_record_doctor FOREIGN KEY (recorded_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE prescription (
    prescription_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    prescription_no VARCHAR(32) NOT NULL UNIQUE,
    admission_id INT UNSIGNED NOT NULL,
    doctor_id INT UNSIGNED NOT NULL,
    prescription_type VARCHAR(16) NOT NULL,
    ordered_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    start_time DATETIME NULL,
    end_time DATETIME NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'SUBMITTED',
    remark VARCHAR(255),
    CONSTRAINT fk_prescription_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_prescription_doctor FOREIGN KEY (doctor_id) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE prescription_item (
    prescription_item_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    prescription_id INT UNSIGNED NOT NULL,
    drug_id INT UNSIGNED NOT NULL,
    dose DECIMAL(10,2) NOT NULL,
    dose_unit VARCHAR(16) NOT NULL,
    route VARCHAR(32) NOT NULL,
    frequency VARCHAR(32) NOT NULL,
    days INT NOT NULL,
    quantity INT NOT NULL,
    unit_price_snapshot DECIMAL(10,2) NOT NULL,
    instruction_text VARCHAR(255),
    CONSTRAINT fk_prescription_item_prescription FOREIGN KEY (prescription_id) REFERENCES prescription(prescription_id),
    CONSTRAINT fk_prescription_item_drug FOREIGN KEY (drug_id) REFERENCES drug(drug_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE exam_order (
    exam_order_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_no VARCHAR(32) NOT NULL UNIQUE,
    admission_id INT UNSIGNED NOT NULL,
    doctor_id INT UNSIGNED NOT NULL,
    ordered_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    priority VARCHAR(16) NOT NULL DEFAULT 'NORMAL',
    status VARCHAR(16) NOT NULL DEFAULT 'ORDERED',
    clinical_note VARCHAR(500),
    CONSTRAINT fk_exam_order_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_exam_order_doctor FOREIGN KEY (doctor_id) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE exam_order_item (
    exam_order_item_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    exam_order_id INT UNSIGNED NOT NULL,
    exam_item_id INT UNSIGNED NOT NULL,
    execution_department_id INT UNSIGNED NULL,
    scheduled_at DATETIME NULL,
    executed_at DATETIME NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ORDERED',
    CONSTRAINT fk_exam_order_item_order FOREIGN KEY (exam_order_id) REFERENCES exam_order(exam_order_id),
    CONSTRAINT fk_exam_order_item_item FOREIGN KEY (exam_item_id) REFERENCES exam_item(exam_item_id),
    CONSTRAINT fk_exam_order_item_dept FOREIGN KEY (execution_department_id) REFERENCES department(department_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE exam_report (
    report_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    exam_order_item_id INT UNSIGNED NOT NULL UNIQUE,
    report_name VARCHAR(255) NOT NULL,
    reported_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reported_by INT UNSIGNED NOT NULL,
    conclusion TEXT,
    status VARCHAR(16) NOT NULL DEFAULT 'PUBLISHED',
    CONSTRAINT fk_report_item FOREIGN KEY (exam_order_item_id) REFERENCES exam_order_item(exam_order_item_id),
    CONSTRAINT fk_report_user FOREIGN KEY (reported_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE exam_result (
    result_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    report_id INT UNSIGNED NOT NULL,
    item_name VARCHAR(128) NOT NULL,
    qualitative_value VARCHAR(128),
    quantitative_value DECIMAL(12,4),
    unit VARCHAR(32),
    reference_range VARCHAR(128),
    abnormal_flag VARCHAR(16),
    remark VARCHAR(255),
    sort_no INT NOT NULL DEFAULT 1,
    CONSTRAINT fk_result_report FOREIGN KEY (report_id) REFERENCES exam_report(report_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE nursing_assessment (
    assessment_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    assessment_type VARCHAR(32) NOT NULL,
    score DECIMAL(8,2),
    risk_level VARCHAR(16),
    measures TEXT,
    assessed_by INT UNSIGNED NOT NULL,
    assessed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    remark VARCHAR(255),
    CONSTRAINT fk_assessment_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_assessment_user FOREIGN KEY (assessed_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE vital_sign (
    vital_sign_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    measured_at DATETIME NOT NULL,
    temperature DECIMAL(4,1),
    pulse INT,
    respiratory_rate INT,
    systolic_bp INT,
    diastolic_bp INT,
    spo2 DECIMAL(5,2),
    measured_by INT UNSIGNED NOT NULL,
    remark VARCHAR(255),
    CONSTRAINT fk_vital_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_vital_user FOREIGN KEY (measured_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE charge (
    charge_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    source_type VARCHAR(16) NOT NULL,
    source_id INT UNSIGNED NULL,
    item_name_snapshot VARCHAR(255) NOT NULL,
    quantity DECIMAL(10,2) NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    occurred_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(16) NOT NULL DEFAULT 'UNSETTLED',
    created_by INT UNSIGNED NOT NULL,
    KEY idx_charge_admission_status (admission_id, status),
    CONSTRAINT fk_charge_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_charge_user FOREIGN KEY (created_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE deposit_transaction (
    deposit_txn_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    txn_type VARCHAR(16) NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    payment_method VARCHAR(16) NOT NULL,
    receipt_no VARCHAR(32) NOT NULL UNIQUE,
    txn_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    operator_id INT UNSIGNED NOT NULL,
    remark VARCHAR(255),
    CONSTRAINT chk_deposit_amount CHECK (amount > 0),
    CONSTRAINT fk_deposit_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_deposit_user FOREIGN KEY (operator_id) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE discharge_settlement (
    settlement_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL UNIQUE,
    total_charge DECIMAL(12,2) NOT NULL,
    deposit_used DECIMAL(12,2) NOT NULL,
    refund_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    additional_payment DECIMAL(12,2) NOT NULL DEFAULT 0,
    settled_at DATETIME NULL,
    settled_by INT UNSIGNED NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    remark VARCHAR(255),
    CONSTRAINT fk_settlement_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_settlement_user FOREIGN KEY (settled_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
