package com.hospital.bootstrap;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** 应用首次启动时生成可重复、满足课程数据量要求的演示数据。 */
@Component
public class DemoDataInitializer implements ApplicationRunner {
    private final JdbcTemplate jdbc;
    private final PasswordEncoder encoder;

    public DemoDataInitializer(JdbcTemplate jdbc, PasswordEncoder encoder) {
        this.jdbc = jdbc;
        this.encoder = encoder;
    }

    /** 在一个事务中创建演示账号、患者、住院和关联记录，失败时不留下半成品数据。 */
    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        Long users = jdbc.queryForObject("SELECT COUNT(*) FROM system_user", Long.class);
        // 以账号是否存在作为幂等条件，避免每次应用启动重复生成课程演示数据。
        if (users != null && users > 0) {
            ensureNurseAccount();
            ensureCaseHomeDemoData();
            ensureExamReportDemoData();
            ensureDiseaseReportDemoData();
            return;
        }

        // Flyway 已预置三类角色和科室；初始化仅查询其主键，不重复插入基础字典。
        long adminRole = id("SELECT role_id FROM role WHERE role_code='SUPER_ADMIN'");
        long admissionRole = id("SELECT role_id FROM role WHERE role_code='ADMISSION'");
        long doctorRole = id("SELECT role_id FROM role WHERE role_code='DOCTOR'");
        long nurseRole = id("SELECT role_id FROM role WHERE role_code='NURSE'");
        long adminDept = id("SELECT department_id FROM department WHERE department_code='ADM'");
        long neuDept = id("SELECT department_id FROM department WHERE department_code='NEU'");
        // 三个账号分别覆盖管理员、住院处和医师的课程演示权限。
        jdbc.update(
                "INSERT INTO system_user(role_id,department_id,username,password_hash,real_name,employee_no) "
                        + "VALUES (?,?,?,?,?,?)",
                adminRole,
                adminDept,
                "admin",
                encoder.encode("Admin123!"),
                "系统管理员",
                "A001");
        jdbc.update(
                "INSERT INTO system_user(role_id,department_id,username,password_hash,real_name,employee_no) "
                        + "VALUES (?,?,?,?,?,?)",
                admissionRole,
                adminDept,
                "admission",
                encoder.encode("Admission123!"),
                "住院处小李",
                "R001");
        jdbc.update(
                "INSERT INTO system_user(role_id,department_id,username,password_hash,real_name,employee_no,"
                        + "license_no) VALUES (?,?,?,?,?,?,?)",
                doctorRole,
                neuDept,
                "doctor",
                encoder.encode("Doctor123!"),
                "张医师",
                "D001",
                "DOC-0001");
        // 护士账号用于演示医嘱执行、护理记录与生命体征写入的独立权限边界。
        jdbc.update(
                "INSERT INTO system_user(role_id,department_id,username,password_hash,real_name,employee_no) "
                        + "VALUES (?,?,?,?,?,?)",
                nurseRole,
                neuDept,
                "nurse",
                encoder.encode("Nurse123!"),
                "李护士",
                "N001");

        // 后续演示业务统一引用这两个操作人，使数据的责任归属完整可查。
        long doctor = id("SELECT user_id FROM system_user WHERE username='doctor'");
        long admissionUser = id("SELECT user_id FROM system_user WHERE username='admission'");
        long nurse = id("SELECT user_id FROM system_user WHERE username='nurse'");
        for (int i = 1; i <= 30; i++) {
            // 使用固定编号和确定性字段生成患者，方便答辩时按样例编号定位记录。
            String patientNo = String.format("P%05d", i);
            jdbc.update(
                    "INSERT INTO patient(patient_no,name,id_card_no,gender,birth_date,phone,address,"
                            + "emergency_contact_name,emergency_contact_phone) VALUES (?,?,?,?,?,?,?,?,?)",
                    patientNo,
                    "演示患者" + i,
                    "3702" + String.format("%014d", i),
                    i % 2 == 0 ? "FEMALE" : "MALE",
                    LocalDate.of(1955 + i % 45, (i % 12) + 1, (i % 27) + 1),
                    "1380000" + String.format("%04d", i),
                    "青岛市示例路" + i + "号",
                    "家属" + i,
                    "1390000" + String.format("%04d", i));
            long patient = id("SELECT patient_id FROM patient WHERE patient_no='" + patientNo + "'");
            // 前五名保持在院以占用五张床，其余患者保留已出院历史用于统计住院天数。
            long bed = (i % 5) + 1;
            String status = i <= 5 ? "IN_HOSPITAL" : "DISCHARGED";
            // 每条住院记录都带有完整的入院信息，已出院样本额外写入出院时间。
            // 为每次住院配套一条主要诊断和病程记录，使疾病统计有真实业务来源。
            jdbc.update(
                    "INSERT INTO admission(patient_id,inpatient_no,medical_record_no,admitting_department_id,"
                            + "current_department_id,attending_doctor_id,current_bed_id,admission_time,"
                            + "discharge_time,nursing_level,fee_type,insurance_type,status,created_by) "
                            + "VALUES (?,?,?,?,?,?,?,DATE_SUB(NOW(),INTERVAL ? DAY),?,?,?,?,?,?)",
                    patient,
                    "IN2026" + String.format("%05d", i),
                    "MR2026" + String.format("%05d", i),
                    neuDept,
                    neuDept,
                    doctor,
                    bed,
                    i + 1,
                    status.equals("DISCHARGED") ? LocalDateTime.now().minusDays(i / 2) : null,
                    i % 3 == 0 ? "LEVEL_1" : "LEVEL_2",
                    "INSURED",
                    "居民医保",
                    status,
                    admissionUser);
            long admission = id(
                    "SELECT admission_id FROM admission WHERE inpatient_no='IN2026"
                            + String.format("%05d", i)
                            + "'");
            jdbc.update(
                    "INSERT INTO diagnosis(admission_id,diagnosis_code,diagnosis_name,diagnosis_type,is_primary,"
                            + "diagnosed_by,status) VALUES (?,?,?,?,TRUE,?,'ACTIVE')",
                    admission,
                    "I63." + (i % 5),
                    i % 2 == 0 ? "脑梗死" : "高血压",
                    i <= 5 ? "ADMISSION" : "DISCHARGE",
                    doctor);
            // 病程记录以已签名状态初始化，便于展示临床文书的完整生命周期结果。
            jdbc.update(
                    "INSERT INTO medical_record(admission_id,record_type,title,content,recorded_by,status,"
                            + "signed_at) VALUES (?,?,?,?,?,'SIGNED',NOW())",
                    admission,
                    "FIRST_COURSE",
                    "首次病程记录",
                    "患者入院后生命体征平稳，拟行进一步检查及治疗。",
                    doctor);
            // 每位患者生成多条生命体征记录，满足课程演示的关联数据规模。
            for (int v = 0; v < 3; v++) {
                jdbc.update(
                        "INSERT INTO vital_sign(admission_id,measured_at,temperature,pulse,heart_rate,respiratory_rate,"
                                + "systolic_bp,diastolic_bp,spo2,pain_score,analgesic_pain_score,breakthrough_pain_score,"
                                + "consciousness,intake_ml,output_ml,measured_by,remark) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                        admission,
                        LocalDateTime.now().minusHours(v * 6L),
                        new BigDecimal("36.5"),
                        70 + i % 12,
                        72 + i % 12,
                        18,
                        120 + i % 15,
                        75 + i % 10,
                        new BigDecimal("98.0"),
                        2,
                        1,
                        0,
                        "清醒",
                        new BigDecimal("300.0"),
                        new BigDecimal("240.0"),
                        doctor,
                        "演示体征");
            }
            // 护理评估与生命体征独立保存，体现护理数据不依附于单条病程记录。
            jdbc.update(
                    "INSERT INTO nursing_assessment(admission_id,assessment_type,score,risk_level,measures,"
                            + "assessed_by) VALUES (?,?,?,?,?,?)",
                    admission,
                    "FALL_RISK",
                    new BigDecimal(30 + i % 20),
                    i % 3 == 0 ? "HIGH" : "LOW",
                    "按护理等级巡视",
                    nurse);
            // 成人护理记录和护理医嘱用于展示护士端真实可执行的工作队列。
            jdbc.update(
                    "INSERT INTO nursing_record(admission_id,record_type,content,pain_score,intake_ml,output_ml,"
                            + "recorded_by) VALUES (?,?,?,?,?,?,?)",
                    admission,
                    "ADULT_NURSING",
                    "患者意识清楚，按护理等级巡视并完成健康宣教。",
                    1,
                    new BigDecimal("500.00"),
                    new BigDecimal("320.00"),
                    nurse);
            jdbc.update(
                    "INSERT INTO care_order(order_no,admission_id,order_type,order_class,order_name,dose,route,"
                            + "frequency,instruction_text,ordered_by) VALUES (?,?,?,?,?,?,?,?,?,?)",
                    "SEED-CO-" + i,
                    admission,
                    "NURSING",
                    "LONG_TERM",
                    "生命体征监测",
                    "1次",
                    "护理观察",
                    "q6h",
                    "记录体温、脉搏、血压及意识状态",
                    doctor);
            // 押金流水为每次住院提供可供结算核对的资金来源。
            jdbc.update(
                    "INSERT INTO deposit_transaction(admission_id,txn_type,amount,payment_method,receipt_no,"
                            + "operator_id,remark) VALUES (?,'DEPOSIT',?,'CASH',?,?,?)",
                    admission,
                    new BigDecimal("2000.00"),
                    "SEED-RC-" + i,
                    admissionUser,
                    "演示押金");
            for (int c = 0; c < 3; c++) {
                // 交替生成药品和检查费用，供费用构成统计展示不同来源。
                boolean isDrugCharge = c % 2 == 0;
                BigDecimal unitPrice = isDrugCharge
                        ? new BigDecimal("18.50")
                        : new BigDecimal("28.00");
                jdbc.update(
                        "INSERT INTO charge(admission_id,source_type,source_id,item_name_snapshot,quantity,"
                                + "unit_price,amount,occurred_at,status,created_by) "
                                + "VALUES (?,?,?,?,1,?,?,NOW(),?,?)",
                        admission,
                        isDrugCharge ? "DRUG" : "EXAM",
                        c + 1,
                        isDrugCharge ? "阿司匹林肠溶片" : "血常规",
                        unitPrice,
                        unitPrice,
                        status.equals("DISCHARGED") ? "SETTLED" : "UNSETTLED",
                        doctor);
            }
            if (status.equals("DISCHARGED")) {
                // 已出院样本同步生成结算单；在院样本保留未结费用以演示结算流程。
                jdbc.update(
                        "INSERT INTO discharge_settlement(admission_id,total_charge,deposit_used,refund_amount,"
                                + "additional_payment,settled_at,settled_by,status) "
                                + "VALUES (?,?,?,?,?,NOW(),?,'SETTLED')",
                        admission,
                        new BigDecimal("65.00"),
                        new BigDecimal("65.00"),
                        new BigDecimal("1935.00"),
                        BigDecimal.ZERO,
                        admissionUser);
            }
        }
        // 与前五条在院住院记录保持一致，初始化完成后这五张床处于占用状态。
        jdbc.update("UPDATE bed SET status='OCCUPIED' WHERE bed_id IN (1,2,3,4,5)");
        ensureCaseHomeDemoData();
        ensureExamReportDemoData();
        ensureDiseaseReportDemoData();
    }

    /** 为已存在的旧演示库补齐护士账号，避免升级迁移后必须重建数据库。 */
    private void ensureNurseAccount() {
        Long existing = jdbc.queryForObject(
                "SELECT COUNT(*) FROM system_user WHERE username='nurse'",
                Long.class);
        if (existing != null && existing > 0) {
            return;
        }
        Long nurseRole = jdbc.queryForObject(
                "SELECT role_id FROM role WHERE role_code='NURSE'",
                Long.class);
        Long department = jdbc.queryForObject(
                "SELECT department_id FROM department WHERE department_code='NEU'",
                Long.class);
        if (nurseRole == null || department == null) {
            return;
        }
        jdbc.update(
                "INSERT INTO system_user(role_id,department_id,username,password_hash,real_name,employee_no) "
                        + "VALUES (?,?,?,?,?,?)",
                nurseRole,
                department,
                "nurse",
                encoder.encode("Nurse123!"),
                "李护士",
                "N001");
    }

    /**
     * 仅补充空白的演示患者资料，并为每次住院创建首页扩展行。
     * 使用 COALESCE 和 INSERT IGNORE 防止升级后覆盖用户已有的真实录入结果。
     */
    private void ensureCaseHomeDemoData() {
        jdbc.update(
                "UPDATE patient SET nationality=COALESCE(nationality,'中国'),ethnicity=COALESCE(ethnicity,'汉族'),"
                        + "occupation=COALESCE(occupation,'职员'),marital_status=COALESCE(marital_status,'MARRIED'),"
                        + "native_place_province=COALESCE(native_place_province,'山东省'),"
                        + "native_place_city=COALESCE(native_place_city,'青岛市'),"
                        + "birth_place_province=COALESCE(birth_place_province,'山东省'),"
                        + "birth_place_city=COALESCE(birth_place_city,'青岛市'),"
                        + "birth_place_county=COALESCE(birth_place_county,'市南区'),"
                        + "current_address_province=COALESCE(current_address_province,'山东省'),"
                        + "current_address_city=COALESCE(current_address_city,'青岛市'),"
                        + "current_address_county=COALESCE(current_address_county,'市南区'),"
                        + "current_address_detail=COALESCE(current_address_detail,address),"
                        + "registered_address_province=COALESCE(registered_address_province,'山东省'),"
                        + "registered_address_city=COALESCE(registered_address_city,'青岛市'),"
                        + "registered_address_county=COALESCE(registered_address_county,'市南区'),"
                        + "registered_address_detail=COALESCE(registered_address_detail,registered_address,address),"
                        + "postal_code=COALESCE(postal_code,'266000'),registered_postal_code=COALESCE(registered_postal_code,'266000'),"
                        + "employer_name=COALESCE(employer_name,'海州示例单位'),"
                        + "employer_address=COALESCE(employer_address,'青岛市示例路'),"
                        + "employer_phone=COALESCE(employer_phone,phone),"
                        + "employer_postal_code=COALESCE(employer_postal_code,'266000'),"
                        + "emergency_contact_relation=COALESCE(emergency_contact_relation,'家属'),"
                        + "emergency_contact_address=COALESCE(emergency_contact_address,address),"
                        + "abo_blood_type=COALESCE(abo_blood_type,'O'),rh_blood_type=COALESCE(rh_blood_type,'POSITIVE') "
                        + "WHERE patient_no REGEXP '^P[0-9]{5}$'");
        jdbc.update(
                "INSERT IGNORE INTO case_home_page(admission_id,admission_count,department_director_id,"
                        + "chief_physician_id,medical_group_leader_id,resident_doctor_id,head_nurse_id,"
                        + "responsible_nurse_id,quality_doctor_id,quality_nurse_id,level_one_nursing_days,"
                        + "level_two_nursing_days,updated_by) "
                        + "SELECT a.admission_id,1,a.attending_doctor_id,a.attending_doctor_id,a.attending_doctor_id,"
                        + "a.attending_doctor_id,n.user_id,n.user_id,a.attending_doctor_id,n.user_id,0,"
                        + "DATEDIFF(COALESCE(a.discharge_time,NOW()),a.admission_time)+1,a.attending_doctor_id "
                        + "FROM admission a LEFT JOIN system_user n ON n.username='nurse' "
                        + "WHERE a.attending_doctor_id IS NOT NULL AND a.inpatient_no LIKE 'IN2026%'");
    }

    /**
     * 为参考工作站的检查抽屉准备可重复运行的住院及门诊报告样例。
     * 使用固定业务号和 NOT EXISTS 防止升级后覆盖或重复写入用户已有数据。
     */
    private void ensureExamReportDemoData() {
        jdbc.update(
                "INSERT IGNORE INTO exam_order(order_no,admission_id,doctor_id,ordered_at,priority,status,clinical_note) "
                        + "SELECT CONCAT('SEED-EXAM-',a.admission_id),a.admission_id,a.attending_doctor_id,"
                        + "DATE_SUB(NOW(),INTERVAL 4 HOUR),'NORMAL','COMPLETED','演示住院头颅影像检查' "
                        + "FROM admission a WHERE a.status='IN_HOSPITAL' AND a.attending_doctor_id IS NOT NULL "
                        + "AND a.inpatient_no LIKE 'IN2026%'");
        jdbc.update(
                "INSERT INTO exam_order_item(exam_order_id,exam_item_id,execution_department_id,executed_at,status) "
                        + "SELECT eo.exam_order_id,ei.exam_item_id,ei.department_id,DATE_SUB(NOW(),INTERVAL 3 HOUR),'REPORTED' "
                        + "FROM exam_order eo JOIN admission a ON a.admission_id=eo.admission_id "
                        + "JOIN exam_item ei ON ei.item_code='E003' "
                        + "WHERE eo.order_no=CONCAT('SEED-EXAM-',a.admission_id) "
                        + "AND NOT EXISTS (SELECT 1 FROM exam_order_item existing "
                        + "WHERE existing.exam_order_id=eo.exam_order_id AND existing.exam_item_id=ei.exam_item_id)");
        jdbc.update(
                "INSERT IGNORE INTO exam_report(exam_order_item_id,report_name,reported_at,reported_by,finding_text,conclusion,status) "
                        + "SELECT oi.exam_order_item_id,'头颅CT平扫',DATE_SUB(NOW(),INTERVAL 2 HOUR),eo.doctor_id,"
                        + "'双侧额叶及基底节区见多发斑点状低密度影，脑室系统形态未见明显扩大。',"
                        + "'腔隙性脑梗死，建议结合临床及必要时复查。','PUBLISHED' "
                        + "FROM exam_order_item oi JOIN exam_order eo ON eo.exam_order_id=oi.exam_order_id "
                        + "WHERE eo.order_no LIKE 'SEED-EXAM-%'");
        jdbc.update(
                "INSERT INTO exam_result(report_id,item_name,qualitative_value,remark,sort_no) "
                        + "SELECT er.report_id,'头颅CT平扫','已完成','双侧额叶及基底节区多发低密度影',1 "
                        + "FROM exam_report er WHERE er.report_name='头颅CT平扫' "
                        + "AND NOT EXISTS (SELECT 1 FROM exam_result existing WHERE existing.report_id=er.report_id)");

        jdbc.update(
                "INSERT IGNORE INTO outpatient_visit(visit_no,patient_id,department_id,doctor_id,visited_at,status,clinical_note) "
                        + "SELECT CONCAT('OP-SEED-',a.patient_id),a.patient_id,a.current_department_id,a.attending_doctor_id,"
                        + "DATE_SUB(a.admission_time,INTERVAL 14 DAY),'COMPLETED','住院前门诊复查' "
                        + "FROM admission a WHERE a.attending_doctor_id IS NOT NULL AND a.inpatient_no LIKE 'IN2026%'");
        jdbc.update(
                "INSERT IGNORE INTO outpatient_exam_order(order_no,outpatient_visit_id,doctor_id,ordered_at,priority,status,clinical_note) "
                        + "SELECT CONCAT('OP-EXAM-',ov.outpatient_visit_id),ov.outpatient_visit_id,ov.doctor_id,"
                        + "DATE_SUB(ov.visited_at,INTERVAL 1 HOUR),'NORMAL','COMPLETED','门诊影像随访' "
                        + "FROM outpatient_visit ov WHERE ov.visit_no LIKE 'OP-SEED-%'");
        jdbc.update(
                "INSERT INTO outpatient_exam_order_item(outpatient_exam_order_id,exam_item_id,execution_department_id,executed_at,status) "
                        + "SELECT oo.outpatient_exam_order_id,ei.exam_item_id,ei.department_id,"
                        + "DATE_ADD(oo.ordered_at,INTERVAL 2 HOUR),'REPORTED' "
                        + "FROM outpatient_exam_order oo JOIN exam_item ei ON ei.item_code='E003' "
                        + "WHERE oo.order_no LIKE 'OP-EXAM-%' AND NOT EXISTS ("
                        + "SELECT 1 FROM outpatient_exam_order_item existing WHERE existing.outpatient_exam_order_id=oo.outpatient_exam_order_id "
                        + "AND existing.exam_item_id=ei.exam_item_id)");
        jdbc.update(
                "INSERT IGNORE INTO outpatient_exam_report(outpatient_exam_order_item_id,report_name,reported_at,reported_by,finding_text,conclusion,status) "
                        + "SELECT oi.outpatient_exam_order_item_id,'门诊头颅CT平扫',DATE_ADD(oo.ordered_at,INTERVAL 3 HOUR),"
                        + "oo.doctor_id,'双侧额叶白质区散在低密度灶，未见急性颅内出血征象。',"
                        + "'慢性缺血性改变，建议神经内科随访。','PUBLISHED' "
                        + "FROM outpatient_exam_order_item oi JOIN outpatient_exam_order oo "
                        + "ON oo.outpatient_exam_order_id=oi.outpatient_exam_order_id WHERE oo.order_no LIKE 'OP-EXAM-%'");
        jdbc.update(
                "INSERT INTO outpatient_exam_result(outpatient_exam_report_id,item_name,qualitative_value,remark,sort_no) "
                        + "SELECT er.outpatient_exam_report_id,'头颅CT平扫','已完成','未见急性出血征象',1 "
                        + "FROM outpatient_exam_report er WHERE er.report_name='门诊头颅CT平扫' "
                        + "AND NOT EXISTS (SELECT 1 FROM outpatient_exam_result existing "
                        + "WHERE existing.outpatient_exam_report_id=er.outpatient_exam_report_id)");
    }

    /**
     * 为疾病上报史准备已提交、已审核、已退回和草稿四种数据库记录。
     * 这些仅是演示库种子数据，页面不会直接写入或依赖其中的患者、疾病和日期。
     */
    private void ensureDiseaseReportDemoData() {
        jdbc.update(
                "INSERT INTO disease_report(admission_id,report_type,disease_name,report_content,status,reported_by,"
                        + "reported_at,created_at) SELECT a.admission_id,'INFECTIOUS','流行性感冒',"
                        + "'演示疾病上报：待审核，出现发热、咳嗽等症状。','SUBMITTED',d.user_id,"
                        + "DATE_SUB(NOW(),INTERVAL 2 DAY),DATE_SUB(NOW(),INTERVAL 3 DAY) FROM admission a "
                        + "JOIN system_user d ON d.username='doctor' WHERE a.inpatient_no='IN20260001' "
                        + "AND NOT EXISTS (SELECT 1 FROM disease_report r WHERE r.admission_id=a.admission_id "
                        + "AND r.report_content LIKE '演示疾病上报：待审核%')");
        jdbc.update(
                "INSERT INTO disease_report(admission_id,report_type,disease_name,report_content,status,reported_by,"
                        + "reported_at,reviewed_by,reviewed_at,review_note,created_at) SELECT a.admission_id,"
                        + "'DEATH_CARD','死亡医学证明','演示疾病上报：已审核', 'APPROVED',d.user_id,"
                        + "DATE_SUB(NOW(),INTERVAL 4 DAY),m.user_id,DATE_SUB(NOW(),INTERVAL 3 DAY),'资料完整，审核通过。',"
                        + "DATE_SUB(NOW(),INTERVAL 5 DAY) FROM admission a JOIN system_user d ON d.username='doctor' "
                        + "JOIN system_user m ON m.username='admin' WHERE a.inpatient_no='IN20260001' "
                        + "AND NOT EXISTS (SELECT 1 FROM disease_report r WHERE r.admission_id=a.admission_id "
                        + "AND r.report_content='演示疾病上报：已审核')");
        jdbc.update(
                "INSERT INTO disease_report(admission_id,report_type,disease_name,report_content,status,reported_by,"
                        + "reported_at,reviewed_by,reviewed_at,review_note,created_at) SELECT a.admission_id,"
                        + "'INFECTIOUS','病毒性肝炎','演示疾病上报：已退回','RETURNED',d.user_id,"
                        + "DATE_SUB(NOW(),INTERVAL 6 DAY),m.user_id,DATE_SUB(NOW(),INTERVAL 5 DAY),'请补充患者接触史。',"
                        + "DATE_SUB(NOW(),INTERVAL 7 DAY) FROM admission a JOIN system_user d ON d.username='doctor' "
                        + "JOIN system_user m ON m.username='admin' WHERE a.inpatient_no='IN20260001' "
                        + "AND NOT EXISTS (SELECT 1 FROM disease_report r WHERE r.admission_id=a.admission_id "
                        + "AND r.report_content='演示疾病上报：已退回')");
        jdbc.update(
                "INSERT INTO disease_report(admission_id,report_type,disease_name,report_content,status,reported_by,"
                        + "created_at) SELECT a.admission_id,'INFECTIOUS','水痘','演示疾病上报：草稿','DRAFT',d.user_id,"
                        + "DATE_SUB(NOW(),INTERVAL 1 DAY) FROM admission a JOIN system_user d ON d.username='doctor' "
                        + "WHERE a.inpatient_no='IN20260001' AND NOT EXISTS (SELECT 1 FROM disease_report r "
                        + "WHERE r.admission_id=a.admission_id AND r.report_content='演示疾病上报：草稿')");
    }

    private long id(String sql) {
        // 此辅助方法仅用于读取已知唯一字典或演示记录的主键。
        return jdbc.queryForObject(sql, Long.class);
    }
}
