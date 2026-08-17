package com.hospital.workstation;

import com.hospital.common.ApiResponse;
import com.hospital.common.BusinessException;
import com.hospital.security.CurrentUser;
import com.hospital.security.JwtUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 提供参考临床工作站的患者上下文、文书、医嘱、护理和上报接口。 */
@RestController
@RequestMapping("/api/v1/workstation")
public class WorkstationController {
    private final JdbcTemplate jdbc;
    private final WorkstationService service;

    public WorkstationController(JdbcTemplate jdbc, WorkstationService service) {
        this.jdbc = jdbc;
        this.service = service;
    }

    /** 查询有权限的在院患者，作为所有临床工作区的左侧患者列表数据源。 */
    @GetMapping("/admissions")
    public ApiResponse<List<Map<String, Object>>> admissions(@RequestParam(required = false) String keyword) {
        JwtUser actor = CurrentUser.get();
        String sql = "SELECT a.admission_id,a.inpatient_no,a.medical_record_no,a.status,p.name AS patient_name,"
                + "p.gender,b.bed_no,d.department_name,u.real_name AS doctor_name "
                + "FROM admission a JOIN patient p ON p.patient_id=a.patient_id "
                + "LEFT JOIN bed b ON b.bed_id=a.current_bed_id "
                + "JOIN department d ON d.department_id=a.current_department_id "
                + "LEFT JOIN system_user u ON u.user_id=a.attending_doctor_id "
                + "WHERE a.status='IN_HOSPITAL'";
        if ("DOCTOR".equals(actor.roleCode())) {
            sql += " AND a.attending_doctor_id=" + actor.userId();
        } else if ("NURSE".equals(actor.roleCode())) {
            sql += " AND a.current_department_id=(SELECT department_id FROM system_user WHERE user_id="
                    + actor.userId() + ")";
        }
        if (keyword != null && !keyword.isBlank()) {
            return ApiResponse.ok(jdbc.queryForList(
                    sql + " AND (p.name LIKE ? OR a.inpatient_no LIKE ? OR b.bed_no LIKE ?) ORDER BY b.bed_no",
                    "%" + keyword + "%",
                    "%" + keyword + "%",
                    "%" + keyword + "%"));
        }
        return ApiResponse.ok(jdbc.queryForList(sql + " ORDER BY b.bed_no,a.admission_time DESC"));
    }

    /** 返回参考界面顶部患者横幅、费用提醒、过敏提示和当前住院摘要。 */
    @GetMapping("/admissions/{admissionId}/context")
    public ApiResponse<Map<String, Object>> patientContext(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        String sql = "SELECT a.*,p.patient_no,p.name AS patient_name,p.gender,p.birth_date,p.height_cm,p.weight_kg,"
                + "p.phone,p.id_type,p.id_card_no,p.nationality,p.occupation,p.marital_status,p.birth_place,"
                + "p.registered_address,p.current_address,p.address,p.postal_code,p.emergency_contact_name,"
                + "p.emergency_contact_relation,p.emergency_contact_phone,d.department_name,b.bed_no,"
                + "u.real_name AS doctor_name,DATEDIFF(NOW(),a.admission_time) + 1 AS stay_days "
                + "FROM admission a JOIN patient p ON p.patient_id=a.patient_id "
                + "JOIN department d ON d.department_id=a.current_department_id "
                + "LEFT JOIN bed b ON b.bed_id=a.current_bed_id "
                + "LEFT JOIN system_user u ON u.user_id=a.attending_doctor_id WHERE a.admission_id=?";
        Map<String, Object> context = jdbc.queryForMap(sql, admissionId);
        List<Map<String, Object>> allergies = jdbc.queryForList(
                "SELECT allergen_name,allergy_type,result,severity,reaction_text FROM patient_allergy "
                        + "WHERE patient_id=? ORDER BY recorded_at DESC",
                context.get("patient_id"));
        BigDecimal deposit = jdbc.queryForObject(
                "SELECT COALESCE(SUM(CASE WHEN txn_type='DEPOSIT' THEN amount ELSE -amount END),0) "
                        + "FROM deposit_transaction WHERE admission_id=?",
                BigDecimal.class,
                admissionId);
        BigDecimal unsettled = jdbc.queryForObject(
                "SELECT COALESCE(SUM(amount),0) FROM charge WHERE admission_id=? AND status='UNSETTLED'",
                BigDecimal.class,
                admissionId);
        return ApiResponse.ok(Map.of(
                "admission", context,
                "allergies", allergies,
                "depositBalance", deposit,
                "unsettledCharge", unsettled,
                "availableBalance", deposit.subtract(unsettled)));
    }

    /** 病案首页一次返回患者主档、住院归档、路径质控和四类诊断，避免前端拼接产生时间差。 */
    @GetMapping("/admissions/{admissionId}/case-home")
    public ApiResponse<Map<String, Object>> caseHome(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        String sql = "SELECT p.*,a.admission_id,a.inpatient_no,a.medical_record_no,a.admission_time,a.discharge_time,"
                + "a.fee_type,a.insurance_type,a.admission_source,a.nursing_level,a.admission_condition,"
                + "a.admission_diagnosis_summary,a.status,h.*,ad.department_name AS admission_department_name,"
                + "cd.department_name AS current_department_name,dd.department_name AS discharge_department_name,"
                + "b.bed_no AS admission_bed_no,att.real_name AS attending_doctor_name,"
                + "dir.real_name AS department_director_name,chief.real_name AS chief_physician_name,"
                + "leader.real_name AS medical_group_leader_name,res.real_name AS resident_doctor_name,"
                + "hn.real_name AS head_nurse_name,rn.real_name AS responsible_nurse_name,"
                + "qd.real_name AS quality_doctor_name,qn.real_name AS quality_nurse_name,"
                + "DATEDIFF(COALESCE(a.discharge_time,NOW()),a.admission_time)+1 AS actual_stay_days,"
                + "(SELECT COUNT(*) FROM patient_allergy pa WHERE pa.patient_id=p.patient_id) AS allergy_count,"
                + "(SELECT status FROM clinical_pathway_enrollment cpe WHERE cpe.admission_id=a.admission_id "
                + "ORDER BY cpe.enrollment_id DESC LIMIT 1) AS pathway_enrollment_status,"
                + "(SELECT CASE WHEN COUNT(*)=0 THEN '未入径' "
                + "WHEN SUM(CASE WHEN t.status='COMPLETED' THEN 1 ELSE 0 END)=COUNT(*) THEN '已完成' "
                + "ELSE CONCAT(SUM(CASE WHEN t.status='COMPLETED' THEN 1 ELSE 0 END),'/',COUNT(*),'项') END "
                + "FROM clinical_pathway_enrollment cpe JOIN clinical_pathway_task t "
                + "ON t.enrollment_id=cpe.enrollment_id WHERE cpe.admission_id=a.admission_id "
                + "AND cpe.enrollment_id=(SELECT MAX(x.enrollment_id) FROM clinical_pathway_enrollment x "
                + "WHERE x.admission_id=a.admission_id)) AS pathway_completion_status,"
                + "(SELECT CASE WHEN COUNT(t.pathway_task_id)=0 THEN '无变异' "
                + "ELSE CONCAT(COUNT(t.pathway_task_id),'项变异') END FROM clinical_pathway_enrollment cpe "
                + "JOIN clinical_pathway_task t ON t.enrollment_id=cpe.enrollment_id "
                + "WHERE cpe.admission_id=a.admission_id AND cpe.enrollment_id=(SELECT MAX(x.enrollment_id) "
                + "FROM clinical_pathway_enrollment x WHERE x.admission_id=a.admission_id) "
                + "AND t.variation_reason IS NOT NULL AND t.variation_reason<> '') AS pathway_variation_status "
                + "FROM admission a JOIN patient p ON p.patient_id=a.patient_id "
                + "JOIN department ad ON ad.department_id=a.admitting_department_id "
                + "JOIN department cd ON cd.department_id=a.current_department_id "
                + "LEFT JOIN case_home_page h ON h.admission_id=a.admission_id "
                + "LEFT JOIN department dd ON dd.department_id=h.discharge_department_id "
                + "LEFT JOIN bed b ON b.bed_id=a.current_bed_id "
                + "LEFT JOIN system_user att ON att.user_id=a.attending_doctor_id "
                + "LEFT JOIN system_user dir ON dir.user_id=h.department_director_id "
                + "LEFT JOIN system_user chief ON chief.user_id=h.chief_physician_id "
                + "LEFT JOIN system_user leader ON leader.user_id=h.medical_group_leader_id "
                + "LEFT JOIN system_user res ON res.user_id=h.resident_doctor_id "
                + "LEFT JOIN system_user hn ON hn.user_id=h.head_nurse_id "
                + "LEFT JOIN system_user rn ON rn.user_id=h.responsible_nurse_id "
                + "LEFT JOIN system_user qd ON qd.user_id=h.quality_doctor_id "
                + "LEFT JOIN system_user qn ON qn.user_id=h.quality_nurse_id WHERE a.admission_id=?";
        Map<String, Object> home = jdbc.queryForMap(sql, admissionId);
        List<Map<String, Object>> diagnoses = jdbc.queryForList(
                "SELECT d.*,u.real_name AS doctor_name FROM diagnosis d JOIN system_user u "
                        + "ON u.user_id=d.diagnosed_by WHERE d.admission_id=? AND d.status='ACTIVE' "
                        + "ORDER BY d.diagnosis_type,d.is_primary DESC,d.diagnosed_at",
                admissionId);
        return ApiResponse.ok(Map.of(
                "home", home,
                "diagnoses", diagnoses,
                "facilityName", "海州市第一人民医院",
                "facilityCode", "HOSPITAL-DEMO-001"));
    }

    /** 医师保存病案首页时，患者主档与本次住院归档信息在同一事务中更新。 */
    @PutMapping("/admissions/{admissionId}/case-home")
    @PreAuthorize("hasRole('DOCTOR')")
    public ApiResponse<Void> saveCaseHome(
            @PathVariable long admissionId,
            @RequestBody CaseHomeRequest request) {
        service.saveCaseHome(admissionId, request, CurrentUser.get());
        return ApiResponse.ok(null);
    }

    /** 病案首页以人员下拉框选择医疗和护理质量人员，避免把姓名作为不可追溯的普通文本保存。 */
    @GetMapping("/case-home/staff")
    @PreAuthorize("hasRole('DOCTOR')")
    public ApiResponse<List<Map<String, Object>>> caseHomeStaff() {
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT u.user_id,u.real_name,r.role_code,d.department_name FROM system_user u "
                        + "JOIN role r ON r.role_id=u.role_id LEFT JOIN department d ON d.department_id=u.department_id "
                        + "WHERE u.status='ACTIVE' AND r.role_code IN ('DOCTOR','NURSE') "
                        + "ORDER BY r.role_code,u.real_name"));
    }

    /** 聚合患者临床数据，供仪表盘和右侧摘要卡片直接展示。 */
    @GetMapping("/admissions/{admissionId}/summary")
    public ApiResponse<Map<String, Object>> summary(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(Map.of(
                "documents", count("SELECT COUNT(*) FROM medical_record WHERE admission_id=?", admissionId),
                "unsignedDocuments", count(
                        "SELECT COUNT(*) FROM medical_record WHERE admission_id=? AND status<>'SIGNED'", admissionId),
                "openCareOrders", count(
                        "SELECT COUNT(*) FROM care_order WHERE admission_id=? AND status='OPEN'", admissionId),
                "reports", count("SELECT COUNT(*) FROM exam_order eo JOIN exam_order_item eoi "
                        + "ON eoi.exam_order_id=eo.exam_order_id WHERE eo.admission_id=? "
                        + "AND eoi.status='REPORTED'", admissionId),
                "pendingPathwayTasks", count("SELECT COUNT(*) FROM clinical_pathway_task t "
                        + "JOIN clinical_pathway_enrollment e ON e.enrollment_id=t.enrollment_id "
                        + "WHERE e.admission_id=? AND t.status='PENDING'", admissionId)));
    }

    @GetMapping("/admissions/{admissionId}/bed-movements")
    public ApiResponse<List<Map<String, Object>>> bedMovements(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        String sql = "SELECT m.*,fd.department_name AS from_department,td.department_name AS to_department,"
                + "fb.bed_no AS from_bed,tb.bed_no AS to_bed,u.real_name AS operator_name "
                + "FROM bed_movement_history m LEFT JOIN department fd ON fd.department_id=m.from_department_id "
                + "LEFT JOIN department td ON td.department_id=m.to_department_id "
                + "LEFT JOIN bed fb ON fb.bed_id=m.from_bed_id LEFT JOIN bed tb ON tb.bed_id=m.to_bed_id "
                + "JOIN system_user u ON u.user_id=m.operated_by WHERE m.admission_id=? ORDER BY m.moved_at DESC";
        return ApiResponse.ok(jdbc.queryForList(sql, admissionId));
    }

    @GetMapping("/document-templates")
    public ApiResponse<List<Map<String, Object>>> documentTemplates(
            @RequestParam(required = false) String category) {
        String sql = "SELECT * FROM document_template WHERE is_active=TRUE";
        if (category != null && !category.isBlank()) {
            return ApiResponse.ok(jdbc.queryForList(sql + " AND document_category=? ORDER BY document_code", category));
        }
        return ApiResponse.ok(jdbc.queryForList(sql + " ORDER BY document_category,document_code"));
    }

    @GetMapping("/admissions/{admissionId}/documents")
    public ApiResponse<List<Map<String, Object>>> documents(
            @PathVariable long admissionId,
            @RequestParam(required = false) String code) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        String sql = "SELECT r.record_id,r.record_type,r.document_code,r.title,r.template_name,r.content,r.content_json,"
                + "r.status,r.version_no,r.recorded_at,r.submitted_at,r.signed_at,r.patient_opinion,"
                + "u.real_name AS author_name,s.real_name AS signer_name FROM medical_record r "
                + "JOIN system_user u ON u.user_id=r.recorded_by LEFT JOIN system_user s ON s.user_id=r.signed_by "
                + "WHERE r.admission_id=?";
        if (code != null && !code.isBlank()) {
            return ApiResponse.ok(jdbc.queryForList(sql + " AND r.document_code=? ORDER BY r.recorded_at DESC", admissionId, code));
        }
        return ApiResponse.ok(jdbc.queryForList(sql + " ORDER BY r.recorded_at DESC", admissionId));
    }

    @PostMapping("/admissions/{admissionId}/documents")
    public ApiResponse<Map<String, Long>> saveDocument(
            @PathVariable long admissionId,
            @Valid @RequestBody DocumentRequest request) {
        long recordId = service.saveDocument(
                admissionId,
                request.templateId(),
                request.documentCode(),
                request.title(),
                request.content(),
                request.contentJson(),
                CurrentUser.get());
        return ApiResponse.ok(Map.of("recordId", recordId));
    }

    @PostMapping("/documents/{recordId}/submit")
    public ApiResponse<Void> submitDocument(@PathVariable long recordId) {
        service.submitDocument(recordId, CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @PostMapping("/documents/{recordId}/sign")
    public ApiResponse<Void> signDocument(@PathVariable long recordId, @RequestBody SignRequest request) {
        service.signDocument(recordId, request.patientOpinion(), CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @PostMapping("/documents/{recordId}/revise")
    public ApiResponse<Map<String, Long>> reviseDocument(
            @PathVariable long recordId,
            @Valid @RequestBody ReasonRequest request) {
        return ApiResponse.ok(Map.of("recordId", service.reviseDocument(recordId, request.reason(), CurrentUser.get())));
    }

    @PostMapping("/documents/{recordId}/void")
    public ApiResponse<Void> voidDocument(@PathVariable long recordId, @Valid @RequestBody ReasonRequest request) {
        service.voidDocument(recordId, request.reason(), CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @GetMapping("/documents/{recordId}/audit")
    public ApiResponse<List<Map<String, Object>>> documentAudit(@PathVariable long recordId) {
        long admissionId = jdbc.queryForObject("SELECT admission_id FROM medical_record WHERE record_id=?", Long.class, recordId);
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT a.*,u.real_name AS actor_name FROM medical_record_audit a JOIN system_user u "
                        + "ON u.user_id=a.actor_id WHERE a.record_id=? ORDER BY a.action_at DESC",
                recordId));
    }

    /** 按模板时限实时计算文书质控，不写入伪造的质控状态。 */
    @GetMapping("/admissions/{admissionId}/quality")
    public ApiResponse<List<Map<String, Object>>> quality(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        String sql = "SELECT t.document_code,t.template_name,t.due_hours,"
                + "MAX(r.status) AS latest_status,MAX(r.recorded_at) AS latest_recorded_at,"
                + "CASE WHEN MAX(r.status)='SIGNED' THEN 'COMPLETED' "
                + "WHEN DATE_ADD(a.admission_time,INTERVAL t.due_hours HOUR)<NOW() THEN 'OVERDUE' "
                + "ELSE 'PENDING' END AS quality_status FROM document_template t CROSS JOIN admission a "
                + "LEFT JOIN medical_record r ON r.admission_id=a.admission_id AND r.document_code=t.document_code "
                + "WHERE a.admission_id=? AND t.due_hours IS NOT NULL AND t.document_category='DOCTOR' "
                + "GROUP BY t.template_id,a.admission_id ORDER BY t.due_hours";
        return ApiResponse.ok(jdbc.queryForList(sql, admissionId));
    }

    @GetMapping("/admissions/{admissionId}/care-orders")
    public ApiResponse<List<Map<String, Object>>> careOrders(
            @PathVariable long admissionId,
            @RequestParam(required = false) String orderClass,
            @RequestParam(required = false) String status) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        String sql = "SELECT o.*,u.real_name AS doctor_name FROM care_order o JOIN system_user u "
                + "ON u.user_id=o.ordered_by WHERE o.admission_id=?";
        if (orderClass != null && !orderClass.isBlank()) {
            sql += " AND o.order_class='" + orderClass.replace("'", "") + "'";
        }
        if (status != null && !status.isBlank()) {
            sql += " AND o.status='" + status.replace("'", "") + "'";
        }
        return ApiResponse.ok(jdbc.queryForList(sql + " ORDER BY o.created_at DESC", admissionId));
    }

    @PostMapping("/admissions/{admissionId}/care-orders")
    public ApiResponse<Map<String, Long>> createCareOrder(
            @PathVariable long admissionId,
            @Valid @RequestBody CareOrderRequest request) {
        long orderId = service.createCareOrder(
                admissionId,
                request.orderType(),
                request.orderClass(),
                request.name(),
                request.dose(),
                request.route(),
                request.frequency(),
                request.startTime(),
                request.endTime(),
                request.instruction(),
                CurrentUser.get());
        return ApiResponse.ok(Map.of("careOrderId", orderId));
    }

    @PostMapping("/care-orders/{orderId}/stop")
    public ApiResponse<Void> stopCareOrder(@PathVariable long orderId, @RequestBody ReasonRequest request) {
        service.changeCareOrderStatus(orderId, "STOP", request.reason(), CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @PostMapping("/care-orders/{orderId}/cancel")
    public ApiResponse<Void> cancelCareOrder(@PathVariable long orderId, @RequestBody ReasonRequest request) {
        service.changeCareOrderStatus(orderId, "CANCEL", request.reason(), CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @PostMapping("/care-orders/{orderId}/execute")
    public ApiResponse<Void> executeCareOrder(@PathVariable long orderId, @RequestBody ExecutionRequest request) {
        service.executeCareOrder(orderId, request.resultNote(), CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @GetMapping("/admissions/{admissionId}/care-order-executions")
    public ApiResponse<List<Map<String, Object>>> careOrderExecutions(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        String sql = "SELECT e.*,o.order_no,o.order_name,o.order_type,u.real_name AS executor_name "
                + "FROM care_order_execution e JOIN care_order o ON o.care_order_id=e.care_order_id "
                + "JOIN system_user u ON u.user_id=e.executed_by WHERE o.admission_id=? "
                + "ORDER BY e.executed_at DESC";
        return ApiResponse.ok(jdbc.queryForList(sql, admissionId));
    }

    @GetMapping("/admissions/{admissionId}/nursing-records")
    public ApiResponse<List<Map<String, Object>>> nursingRecords(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT n.*,u.real_name AS nurse_name FROM nursing_record n JOIN system_user u "
                        + "ON u.user_id=n.recorded_by WHERE n.admission_id=? ORDER BY n.recorded_at DESC",
                admissionId));
    }

    @PostMapping("/admissions/{admissionId}/nursing-records")
    public ApiResponse<Map<String, Long>> createNursingRecord(
            @PathVariable long admissionId,
            @Valid @RequestBody NursingRecordRequest request) {
        return ApiResponse.ok(Map.of("nursingRecordId", service.createNursingRecord(
                admissionId,
                request.recordType(),
                request.content(),
                request.painScore(),
                request.intakeMl(),
                request.outputMl(),
                CurrentUser.get())));
    }

    @GetMapping("/admissions/{admissionId}/nursing-assessments")
    public ApiResponse<List<Map<String, Object>>> nursingAssessments(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT n.*,u.real_name AS assessor_name FROM nursing_assessment n JOIN system_user u "
                        + "ON u.user_id=n.assessed_by WHERE n.admission_id=? ORDER BY n.assessed_at DESC",
                admissionId));
    }

    @PostMapping("/admissions/{admissionId}/nursing-assessments")
    public ApiResponse<Void> createNursingAssessment(
            @PathVariable long admissionId,
            @Valid @RequestBody NursingAssessmentRequest request) {
        service.requireNurseWrite(admissionId, CurrentUser.get());
        jdbc.update(
                "INSERT INTO nursing_assessment(admission_id,assessment_type,score,risk_level,measures,assessed_by,"
                        + "remark) VALUES (?,?,?,?,?,?,?)",
                admissionId,
                request.assessmentType(),
                request.score(),
                request.riskLevel(),
                request.measures(),
                CurrentUser.get().userId(),
                request.remark());
        return ApiResponse.ok(null);
    }

    /** 护士按测量时间写入生命体征，时间序列直接供体温单和趋势表使用。 */
    @PostMapping("/admissions/{admissionId}/vital-signs")
    public ApiResponse<Void> createVitalSign(
            @PathVariable long admissionId,
            @Valid @RequestBody VitalSignRequest request) {
        service.requireNurseWrite(admissionId, CurrentUser.get());
        jdbc.update(
                "INSERT INTO vital_sign(admission_id,measured_at,temperature,pulse,respiratory_rate,systolic_bp,"
                        + "diastolic_bp,spo2,pain_score,consciousness,intake_ml,output_ml,measured_by,remark) "
                        + "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                admissionId,
                request.measuredAt() == null ? LocalDateTime.now() : request.measuredAt(),
                request.temperature(),
                request.pulse(),
                request.respiratoryRate(),
                request.systolicBp(),
                request.diastolicBp(),
                request.spo2(),
                request.painScore(),
                request.consciousness(),
                request.intakeMl(),
                request.outputMl(),
                CurrentUser.get().userId(),
                request.remark());
        return ApiResponse.ok(null);
    }

    @GetMapping("/admissions/{admissionId}/temperature-chart")
    public ApiResponse<List<Map<String, Object>>> temperatureChart(
            @PathVariable long admissionId,
            @RequestParam(required = false) LocalDateTime from,
            @RequestParam(required = false) LocalDateTime to) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        String sql = "SELECT measured_at,temperature,pulse,respiratory_rate,systolic_bp,diastolic_bp,spo2,"
                + "pain_score,consciousness,intake_ml,output_ml FROM vital_sign WHERE admission_id=?";
        if (from != null && to != null) {
            return ApiResponse.ok(jdbc.queryForList(sql + " AND measured_at BETWEEN ? AND ? ORDER BY measured_at", admissionId, from, to));
        }
        return ApiResponse.ok(jdbc.queryForList(sql + " ORDER BY measured_at", admissionId));
    }

    @GetMapping("/admissions/{admissionId}/diagnoses")
    public ApiResponse<List<Map<String, Object>>> diagnoses(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT d.*,u.real_name AS doctor_name FROM diagnosis d JOIN system_user u "
                        + "ON u.user_id=d.diagnosed_by WHERE d.admission_id=? ORDER BY d.diagnosed_at DESC",
                admissionId));
    }

    /** 诊断勾选删除采用作废状态，保留原始记录供病案审计和责任追踪。 */
    @DeleteMapping("/admissions/{admissionId}/diagnoses")
    public ApiResponse<Void> deleteDiagnoses(
            @PathVariable long admissionId,
            @RequestBody DiagnosisDeleteRequest request) {
        service.deleteDiagnoses(admissionId, request.diagnosisIds(), CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @PostMapping("/admissions/{admissionId}/diagnoses")
    public ApiResponse<Void> createDiagnosis(
            @PathVariable long admissionId,
            @Valid @RequestBody DiagnosisRequest request) {
        service.requireDoctorWrite(admissionId, CurrentUser.get());
        if (request.primary()) {
            // 同一诊断阶段只能有一个主要诊断，先撤销旧标志再写入本次诊断。
            jdbc.update(
                    "UPDATE diagnosis SET is_primary=FALSE WHERE admission_id=? AND diagnosis_type=?",
                    admissionId,
                    request.diagnosisType());
        }
        jdbc.update(
                "INSERT INTO diagnosis(admission_id,diagnosis_code,diagnosis_name,diagnosis_type,is_primary,"
                        + "predecessor,diagnosis_note,additional_code,infectious_disease,body_position,body_site,"
                        + "t_stage,n_stage,m_stage,admission_condition,treated,efficacy,pathology_no,"
                        + "tumor_diagnosis_basis,pathologist,pathology_technician,diagnosed_by) "
                        + "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                admissionId,
                request.diagnosisCode(),
                request.diagnosisName(),
                request.diagnosisType(),
                request.primary(),
                request.predecessor(),
                request.diagnosisNote(),
                request.additionalCode(),
                Boolean.TRUE.equals(request.infectiousDisease()),
                request.bodyPosition(),
                request.bodySite(),
                request.tStage(),
                request.nStage(),
                request.mStage(),
                request.admissionCondition(),
                request.treated(),
                request.efficacy(),
                request.pathologyNo(),
                request.tumorDiagnosisBasis(),
                request.pathologist(),
                request.pathologyTechnician(),
                CurrentUser.get().userId());
        return ApiResponse.ok(null);
    }

    @GetMapping("/pathway-templates")
    public ApiResponse<List<Map<String, Object>>> pathwayTemplates() {
        return ApiResponse.ok(jdbc.queryForList("SELECT * FROM clinical_pathway_template WHERE status='ACTIVE' ORDER BY pathway_code"));
    }

    @GetMapping("/admissions/{admissionId}/pathways")
    public ApiResponse<List<Map<String, Object>>> pathways(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT e.*,p.pathway_name FROM clinical_pathway_enrollment e JOIN clinical_pathway_template p "
                        + "ON p.pathway_template_id=e.pathway_template_id WHERE e.admission_id=? ORDER BY e.enrolled_at DESC",
                admissionId));
    }

    @GetMapping("/pathways/{enrollmentId}/tasks")
    public ApiResponse<List<Map<String, Object>>> pathwayTasks(@PathVariable long enrollmentId) {
        long admissionId = jdbc.queryForObject(
                "SELECT admission_id FROM clinical_pathway_enrollment WHERE enrollment_id=?",
                Long.class,
                enrollmentId);
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT t.*,u.real_name AS completed_name FROM clinical_pathway_task t LEFT JOIN system_user u "
                        + "ON u.user_id=t.completed_by WHERE enrollment_id=? ORDER BY day_no,pathway_task_id",
                enrollmentId));
    }

    @PostMapping("/admissions/{admissionId}/pathways")
    public ApiResponse<Map<String, Long>> enrollPathway(
            @PathVariable long admissionId,
            @Valid @RequestBody PathwayEnrollmentRequest request) {
        return ApiResponse.ok(Map.of("enrollmentId", service.enrollPathway(
                admissionId,
                request.templateId(),
                CurrentUser.get())));
    }

    @PostMapping("/pathway-tasks/{taskId}/complete")
    public ApiResponse<Void> completePathwayTask(@PathVariable long taskId, @RequestBody VariationRequest request) {
        service.completePathwayTask(taskId, request.variationReason(), CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @GetMapping("/admissions/{admissionId}/disease-reports")
    public ApiResponse<List<Map<String, Object>>> diseaseReports(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT r.*,u.real_name AS reporter_name,s.real_name AS reviewer_name FROM disease_report r "
                        + "JOIN system_user u ON u.user_id=r.reported_by LEFT JOIN system_user s "
                        + "ON s.user_id=r.reviewed_by WHERE r.admission_id=? ORDER BY r.disease_report_id DESC",
                admissionId));
    }

    /** 管理员审核队列跨患者汇总待审上报，医生端仍只查看自己负责患者的历史。 */
    @GetMapping("/disease-reports")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public ApiResponse<List<Map<String, Object>>> allDiseaseReports() {
        String sql = "SELECT r.*,p.name AS patient_name,a.inpatient_no,u.real_name AS reporter_name "
                + "FROM disease_report r JOIN admission a ON a.admission_id=r.admission_id "
                + "JOIN patient p ON p.patient_id=a.patient_id JOIN system_user u ON u.user_id=r.reported_by "
                + "ORDER BY CASE WHEN r.status='SUBMITTED' THEN 0 ELSE 1 END,r.disease_report_id DESC";
        return ApiResponse.ok(jdbc.queryForList(sql));
    }

    @GetMapping("/disease-report-types")
    public ApiResponse<List<Map<String, Object>>> diseaseReportTypes() {
        return ApiResponse.ok(jdbc.queryForList("SELECT * FROM disease_report_type WHERE status='ACTIVE' ORDER BY type_code"));
    }

    @PostMapping("/admissions/{admissionId}/disease-reports")
    public ApiResponse<Map<String, Long>> createDiseaseReport(
            @PathVariable long admissionId,
            @Valid @RequestBody DiseaseReportRequest request) {
        return ApiResponse.ok(Map.of("diseaseReportId", service.createDiseaseReport(
                admissionId,
                request.reportType(),
                request.diseaseName(),
                request.content(),
                CurrentUser.get())));
    }

    @PostMapping("/disease-reports/{reportId}/submit")
    public ApiResponse<Void> submitDiseaseReport(@PathVariable long reportId) {
        service.submitDiseaseReport(reportId, CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @PostMapping("/disease-reports/{reportId}/review")
    public ApiResponse<Void> reviewDiseaseReport(
            @PathVariable long reportId,
            @Valid @RequestBody DiseaseReviewRequest request) {
        service.reviewDiseaseReport(reportId, request.approved(), request.note(), CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @GetMapping("/admissions/{admissionId}/surgery-applications")
    public ApiResponse<List<Map<String, Object>>> surgeryApplications(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT s.*,u.real_name AS doctor_name FROM surgery_application s JOIN system_user u "
                        + "ON u.user_id=s.applied_by WHERE s.admission_id=? ORDER BY s.applied_at DESC",
                admissionId));
    }

    @PostMapping("/admissions/{admissionId}/surgery-applications")
    @PreAuthorize("hasRole('DOCTOR')")
    public ApiResponse<Void> createSurgeryApplication(
            @PathVariable long admissionId,
            @Valid @RequestBody SurgeryRequest request) {
        service.requireDoctorWrite(admissionId, CurrentUser.get());
        jdbc.update(
                "INSERT INTO surgery_application(admission_id,surgery_name,surgery_level,planned_at,diagnosis_summary,"
                        + "risk_note,applied_by) VALUES (?,?,?,?,?,?,?)",
                admissionId,
                request.surgeryName(),
                request.surgeryLevel(),
                request.plannedAt(),
                request.diagnosisSummary(),
                request.riskNote(),
                CurrentUser.get().userId());
        return ApiResponse.ok(null);
    }

    @GetMapping("/admissions/{admissionId}/consultations")
    public ApiResponse<List<Map<String, Object>>> consultations(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT c.*,d.department_name,u.real_name AS requester_name FROM consultation_request c "
                        + "JOIN department d ON d.department_id=c.target_department_id JOIN system_user u "
                        + "ON u.user_id=c.requested_by WHERE c.admission_id=? ORDER BY c.requested_at DESC",
                admissionId));
    }

    @PostMapping("/admissions/{admissionId}/consultations")
    @PreAuthorize("hasRole('DOCTOR')")
    public ApiResponse<Void> createConsultation(
            @PathVariable long admissionId,
            @Valid @RequestBody ConsultationRequest request) {
        service.requireDoctorWrite(admissionId, CurrentUser.get());
        jdbc.update(
                "INSERT INTO consultation_request(admission_id,target_department_id,consultation_type,request_reason,"
                        + "requested_by) VALUES (?,?,?,?,?)",
                admissionId,
                request.targetDepartmentId(),
                request.consultationType(),
                request.reason(),
                CurrentUser.get().userId());
        return ApiResponse.ok(null);
    }

    @GetMapping("/admissions/{admissionId}/reports")
    public ApiResponse<List<Map<String, Object>>> reports(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        String sql = "SELECT er.*,ei.item_name,eoi.status AS item_status,eo.order_no,"
                + "(SELECT COUNT(*) FROM report_attachment ra WHERE ra.report_id=er.report_id) AS attachment_count "
                + "FROM exam_order eo JOIN exam_order_item eoi ON eoi.exam_order_id=eo.exam_order_id "
                + "JOIN exam_item ei ON ei.exam_item_id=eoi.exam_item_id LEFT JOIN exam_report er "
                + "ON er.exam_order_item_id=eoi.exam_order_item_id WHERE eo.admission_id=? ORDER BY eo.ordered_at DESC";
        return ApiResponse.ok(jdbc.queryForList(sql, admissionId));
    }

    @GetMapping("/reports/{reportId}/attachments")
    public ApiResponse<List<Map<String, Object>>> reportAttachments(@PathVariable long reportId) {
        long admissionId = jdbc.queryForObject(
                "SELECT eo.admission_id FROM exam_report r JOIN exam_order_item i ON i.exam_order_item_id=r.exam_order_item_id "
                        + "JOIN exam_order eo ON eo.exam_order_id=i.exam_order_id WHERE r.report_id=?",
                Long.class,
                reportId);
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(jdbc.queryForList("SELECT * FROM report_attachment WHERE report_id=?", reportId));
    }

    @PostMapping("/admissions/{admissionId}/exports")
    public ApiResponse<Map<String, Object>> requestExport(
            @PathVariable long admissionId,
            @Valid @RequestBody ExportRequest request) {
        long taskId = service.requestExport(admissionId, request.exportType(), request.sourceId(), CurrentUser.get());
        return ApiResponse.ok(Map.of(
                "exportTaskId", taskId,
                "status", "PENDING_TEMPLATE",
                "message", "尚未配置正式 PDF 模板，已保留导出任务。"));
    }

    @GetMapping("/admissions/{admissionId}/exports")
    public ApiResponse<List<Map<String, Object>>> exports(@PathVariable long admissionId) {
        service.requireReadAccess(admissionId, CurrentUser.get());
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT e.*,u.real_name AS requester_name FROM export_task e JOIN system_user u "
                        + "ON u.user_id=e.requested_by WHERE e.admission_id=? ORDER BY e.requested_at DESC",
                admissionId));
    }

    /** 管理员可增加表单模板，字段模式保持为字符串数组，前端无需发布即可渲染。 */
    @PostMapping("/admin/document-templates")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public ApiResponse<Void> createDocumentTemplate(@Valid @RequestBody TemplateRequest request) {
        jdbc.update(
                "INSERT INTO document_template(document_code,template_name,document_category,field_schema,due_hours,"
                        + "created_by) VALUES (?,?,?,?,?,?)",
                request.documentCode(),
                request.templateName(),
                request.category(),
                request.fieldSchema(),
                request.dueHours(),
                CurrentUser.get().userId());
        return ApiResponse.ok(null);
    }

    @PostMapping("/admin/disease-report-types")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public ApiResponse<Void> createDiseaseReportType(@Valid @RequestBody DiseaseReportTypeRequest request) {
        jdbc.update(
                "INSERT INTO disease_report_type(type_code,type_name,created_by) VALUES (?,?,?)",
                request.code(),
                request.name(),
                CurrentUser.get().userId());
        return ApiResponse.ok(null);
    }

    /** 管理员维护临床路径目录；路径任务可先使用默认模板任务再按课程演示扩充。 */
    @PostMapping("/admin/pathway-templates")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public ApiResponse<Void> createPathwayTemplate(@Valid @RequestBody PathwayTemplateRequest request) {
        jdbc.update(
                "INSERT INTO clinical_pathway_template(pathway_code,pathway_name,diagnosis_hint,created_by) "
                        + "VALUES (?,?,?,?)",
                request.code(),
                request.name(),
                request.diagnosisHint(),
                CurrentUser.get().userId());
        return ApiResponse.ok(null);
    }

    private long count(String sql, long admissionId) {
        Long value = jdbc.queryForObject(sql, Long.class, admissionId);
        return value == null ? 0 : value;
    }

    public record DocumentRequest(
            @NotNull Long templateId,
            String documentCode,
            String title,
            @NotBlank String content,
            String contentJson) {
    }

    public record SignRequest(String patientOpinion) {
    }

    public record ReasonRequest(@NotBlank String reason) {
    }

    public record CareOrderRequest(
            @NotBlank String orderType,
            @NotBlank String orderClass,
            @NotBlank String name,
            String dose,
            String route,
            String frequency,
            LocalDateTime startTime,
            LocalDateTime endTime,
            String instruction) {
    }

    public record ExecutionRequest(String resultNote) {
    }

    public record NursingRecordRequest(
            @NotBlank String recordType,
            @NotBlank String content,
            Integer painScore,
            BigDecimal intakeMl,
            BigDecimal outputMl) {
    }

    public record NursingAssessmentRequest(
            @NotBlank String assessmentType,
            BigDecimal score,
            String riskLevel,
            String measures,
            String remark) {
    }

    public record VitalSignRequest(
            LocalDateTime measuredAt,
            BigDecimal temperature,
            Integer pulse,
            Integer respiratoryRate,
            Integer systolicBp,
            Integer diastolicBp,
            BigDecimal spo2,
            Integer painScore,
            String consciousness,
            BigDecimal intakeMl,
            BigDecimal outputMl,
            String remark) {
    }

    public record DiagnosisRequest(
            String diagnosisCode,
            @NotBlank String diagnosisName,
            @NotBlank String diagnosisType,
            boolean primary,
            String predecessor,
            String diagnosisNote,
            String additionalCode,
            Boolean infectiousDisease,
            String bodyPosition,
            String bodySite,
            String tStage,
            String nStage,
            String mStage,
            String admissionCondition,
            Boolean treated,
            String efficacy,
            String pathologyNo,
            String tumorDiagnosisBasis,
            String pathologist,
            String pathologyTechnician) {
    }

    public record DiagnosisDeleteRequest(List<Long> diagnosisIds) {
    }

    public record PathwayEnrollmentRequest(@NotNull Long templateId) {
    }

    public record VariationRequest(String variationReason) {
    }

    public record DiseaseReportRequest(
            @NotBlank String reportType,
            @NotBlank String diseaseName,
            @NotBlank String content) {
    }

    public record DiseaseReviewRequest(@NotNull Boolean approved, String note) {
    }

    public record SurgeryRequest(
            @NotBlank String surgeryName,
            String surgeryLevel,
            LocalDateTime plannedAt,
            String diagnosisSummary,
            String riskNote) {
    }

    public record ConsultationRequest(
            @NotNull Long targetDepartmentId,
            @NotBlank String consultationType,
            @NotBlank String reason) {
    }

    public record ExportRequest(@NotBlank String exportType, Long sourceId) {
    }

    public record TemplateRequest(
            @NotBlank String documentCode,
            @NotBlank String templateName,
            @NotBlank String category,
            @NotBlank String fieldSchema,
            Integer dueHours) {
    }

    public record DiseaseReportTypeRequest(@NotBlank String code, @NotBlank String name) {
    }

    public record PathwayTemplateRequest(
            @NotBlank String code,
            @NotBlank String name,
            String diagnosisHint) {
    }
}
