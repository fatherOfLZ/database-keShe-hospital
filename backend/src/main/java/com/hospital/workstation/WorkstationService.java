package com.hospital.workstation;

import com.hospital.common.BusinessException;
import com.hospital.security.JwtUser;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 封装临床工作站文书、护理、医嘱和上报等跨表流程。 */
@Service
public class WorkstationService {
    private static final DateTimeFormatter NUMBER_TIME = DateTimeFormatter.ofPattern("yyyyMMddHHmmssSSS");

    private final JdbcTemplate jdbc;

    public WorkstationService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** 按岗位校验住院数据范围；管理员仅允许读取，不允许代替临床岗位写入。 */
    public void requireReadAccess(long admissionId, JwtUser actor) {
        Map<String, Object> admission = jdbc.queryForMap(
                "SELECT a.status,a.attending_doctor_id,a.current_department_id,u.department_id AS doctor_department_id "
                        + "FROM admission a LEFT JOIN system_user u ON u.user_id=a.attending_doctor_id "
                        + "WHERE a.admission_id=?",
                admissionId);
        if ("SUPER_ADMIN".equals(actor.roleCode()) || "ADMISSION".equals(actor.roleCode())) {
            return;
        }
        if ("DOCTOR".equals(actor.roleCode())) {
            Object doctorId = admission.get("attending_doctor_id");
            if (doctorId != null && ((Number) doctorId).longValue() == actor.userId()) {
                return;
            }
            throw new BusinessException("只能查阅本人负责患者的临床资料");
        }
        if ("NURSE".equals(actor.roleCode())) {
            Long userDepartment = jdbc.queryForObject(
                    "SELECT department_id FROM system_user WHERE user_id=?",
                    Long.class,
                    actor.userId());
            Object currentDepartment = admission.get("current_department_id");
            if (userDepartment != null && currentDepartment != null
                    && userDepartment.longValue() == ((Number) currentDepartment).longValue()) {
                return;
            }
            throw new BusinessException("只能查阅本科室患者的护理资料");
        }
        throw new BusinessException("当前账号无权访问住院临床资料");
    }

    /** 医师写入前同时校验责任医师、在院状态和禁止管理员代写的规则。 */
    public void requireDoctorWrite(long admissionId, JwtUser actor) {
        if (!"DOCTOR".equals(actor.roleCode())) {
            throw new BusinessException("该操作仅限责任医师办理");
        }
        Map<String, Object> admission = jdbc.queryForMap(
                "SELECT status,attending_doctor_id FROM admission WHERE admission_id=?",
                admissionId);
        if (!"IN_HOSPITAL".equals(admission.get("status"))) {
            throw new BusinessException("患者当前未处于住院状态");
        }
        Object doctorId = admission.get("attending_doctor_id");
        if (doctorId == null || ((Number) doctorId).longValue() != actor.userId()) {
            throw new BusinessException("只能维护本人负责患者的临床资料");
        }
    }

    /** 护士写入前校验当前科室归属，防止跨病区维护护理记录。 */
    public void requireNurseWrite(long admissionId, JwtUser actor) {
        if (!"NURSE".equals(actor.roleCode())) {
            throw new BusinessException("该操作仅限护士办理");
        }
        requireReadAccess(admissionId, actor);
        String status = jdbc.queryForObject(
                "SELECT status FROM admission WHERE admission_id=?",
                String.class,
                admissionId);
        if (!"IN_HOSPITAL".equals(status)) {
            throw new BusinessException("患者当前未处于住院状态");
        }
    }

    /** 批量作废病案诊断，并校验每个 ID 都属于当前住院记录，避免跨患者误删。 */
    @Transactional
    public void deleteDiagnoses(long admissionId, List<Long> diagnosisIds, JwtUser actor) {
        requireDoctorWrite(admissionId, actor);
        if (diagnosisIds == null || diagnosisIds.isEmpty()) {
            throw new BusinessException("请先勾选要删除的诊断");
        }
        String placeholders = String.join(",", diagnosisIds.stream().map(id -> "?").toList());
        List<Object> parameters = new java.util.ArrayList<>();
        parameters.add(admissionId);
        parameters.addAll(diagnosisIds);
        int updated = jdbc.update(
                "UPDATE diagnosis SET status='VOID' WHERE admission_id=? AND status='ACTIVE' "
                        + "AND diagnosis_id IN (" + placeholders + ")",
                parameters.toArray());
        if (updated != diagnosisIds.size()) {
            throw new BusinessException("存在不属于当前住院记录或已作废的诊断");
        }
    }

    /**
     * 病案首页一次提交会同时更新患者主档和本次住院归档字段。
     * 两张表必须保持同一版本，任一外键或字段校验失败时整体回滚。
     */
    @Transactional
    public void saveCaseHome(long admissionId, CaseHomeRequest request, JwtUser actor) {
        requireDoctorWrite(admissionId, actor);
        long patientId = jdbc.queryForObject(
                "SELECT patient_id FROM admission WHERE admission_id=?",
                Long.class,
                admissionId);

        jdbc.update(
                "UPDATE patient SET id_type=?,id_card_no=?,nationality=?,ethnicity=?,occupation=?,marital_status=?,"
                        + "native_place_province=?,native_place_city=?,birth_place_province=?,birth_place_city=?,"
                        + "birth_place_county=?,birth_place_detail=?,current_address_province=?,"
                        + "current_address_city=?,current_address_county=?,current_address_detail=?,postal_code=?,phone=?,"
                        + "registered_address_province=?,registered_address_city=?,registered_address_county=?,"
                        + "registered_address_detail=?,registered_postal_code=?,employer_name=?,employer_address=?,"
                        + "employer_phone=?,employer_postal_code=?,emergency_contact_name=?,"
                        + "emergency_contact_relation=?,emergency_contact_address=?,emergency_contact_phone=?,"
                        + "abo_blood_type=?,rh_blood_type=? WHERE patient_id=?",
                valueOrDefault(request.idType(), "ID_CARD"),
                request.idCardNo(),
                request.nationality(),
                request.ethnicity(),
                request.occupation(),
                request.maritalStatus(),
                request.nativePlaceProvince(),
                request.nativePlaceCity(),
                request.birthPlaceProvince(),
                request.birthPlaceCity(),
                request.birthPlaceCounty(),
                request.birthPlaceDetail(),
                request.currentAddressProvince(),
                request.currentAddressCity(),
                request.currentAddressCounty(),
                request.currentAddressDetail(),
                request.postalCode(),
                request.phone(),
                request.registeredAddressProvince(),
                request.registeredAddressCity(),
                request.registeredAddressCounty(),
                request.registeredAddressDetail(),
                request.registeredPostalCode(),
                request.employerName(),
                request.employerAddress(),
                request.employerPhone(),
                request.employerPostalCode(),
                request.emergencyContactName(),
                request.emergencyContactRelation(),
                request.emergencyContactAddress(),
                request.emergencyContactPhone(),
                request.aboBloodType(),
                request.rhBloodType(),
                patientId);

        jdbc.update(
                "UPDATE admission SET fee_type=?,insurance_type=?,admission_source=? WHERE admission_id=?",
                valueOrDefault(request.feeType(), "SELF_PAY"),
                request.insuranceType(),
                valueOrDefault(request.admissionSource(), "OUTPATIENT"),
                admissionId);

        jdbc.update(
                "INSERT INTO case_home_page(admission_id,admission_count,discharge_department_id,discharge_bed_no,"
                        + "discharge_method,readmission_within_31_days,interhospital_operation,department_director_id,"
                        + "chief_physician_id,medical_group_leader_id,resident_doctor_id,head_nurse_id,"
                        + "responsible_nurse_id,quality_doctor_id,quality_nurse_id,quality_control_date,"
                        + "special_nursing_days,level_one_nursing_days,level_two_nursing_days,level_three_nursing_days,"
                        + "updated_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
                        + "ON DUPLICATE KEY UPDATE admission_count=VALUES(admission_count),"
                        + "discharge_department_id=VALUES(discharge_department_id),"
                        + "discharge_bed_no=VALUES(discharge_bed_no),discharge_method=VALUES(discharge_method),"
                        + "readmission_within_31_days=VALUES(readmission_within_31_days),"
                        + "interhospital_operation=VALUES(interhospital_operation),"
                        + "department_director_id=VALUES(department_director_id),"
                        + "chief_physician_id=VALUES(chief_physician_id),"
                        + "medical_group_leader_id=VALUES(medical_group_leader_id),"
                        + "resident_doctor_id=VALUES(resident_doctor_id),head_nurse_id=VALUES(head_nurse_id),"
                        + "responsible_nurse_id=VALUES(responsible_nurse_id),"
                        + "quality_doctor_id=VALUES(quality_doctor_id),quality_nurse_id=VALUES(quality_nurse_id),"
                        + "quality_control_date=VALUES(quality_control_date),"
                        + "special_nursing_days=VALUES(special_nursing_days),"
                        + "level_one_nursing_days=VALUES(level_one_nursing_days),"
                        + "level_two_nursing_days=VALUES(level_two_nursing_days),"
                        + "level_three_nursing_days=VALUES(level_three_nursing_days),updated_by=VALUES(updated_by)",
                admissionId,
                valueOrDefault(request.admissionCount(), 1),
                request.dischargeDepartmentId(),
                request.dischargeBedNo(),
                request.dischargeMethod(),
                request.readmissionWithin31Days(),
                request.interhospitalOperation(),
                request.departmentDirectorId(),
                request.chiefPhysicianId(),
                request.medicalGroupLeaderId(),
                request.residentDoctorId(),
                request.headNurseId(),
                request.responsibleNurseId(),
                request.qualityDoctorId(),
                request.qualityNurseId(),
                request.qualityControlDate(),
                valueOrDefault(request.specialNursingDays(), 0),
                valueOrDefault(request.levelOneNursingDays(), 0),
                valueOrDefault(request.levelTwoNursingDays(), 0),
                valueOrDefault(request.levelThreeNursingDays(), 0),
                actor.userId());
    }

    private <T> T valueOrDefault(T value, T defaultValue) {
        return value == null ? defaultValue : value;
    }

    /** 新建或保存草稿文书，模板字段内容以 JSON 保存，避免为每种文书单独建表。 */
    @Transactional
    public long saveDocument(
            long admissionId,
            Long templateId,
            String documentCode,
            String title,
            String content,
            String contentJson,
            JwtUser actor) {
        requireDoctorWrite(admissionId, actor);
        Map<String, Object> template = jdbc.queryForMap(
                "SELECT template_name,document_code FROM document_template WHERE template_id=? AND is_active=TRUE",
                templateId);
        String resolvedCode = documentCode == null || documentCode.isBlank()
                ? template.get("document_code").toString()
                : documentCode;
        String resolvedTitle = title == null || title.isBlank()
                ? template.get("template_name").toString()
                : title;
        jdbc.update(
                "INSERT INTO medical_record(admission_id,record_type,document_code,title,template_name,content,"
                        + "content_json,recorded_by,status,version_no) VALUES (?,?,?,?,?,?,?,?,'DRAFT',1)",
                admissionId,
                resolvedCode,
                resolvedCode,
                resolvedTitle,
                template.get("template_name"),
                content,
                contentJson,
                actor.userId());
        long recordId = lastInsertId();
        audit(recordId, "CREATE", "创建文书草稿", actor.userId());
        return recordId;
    }

    /** 提交文书后禁止直接覆盖内容，待签名或修订流程继续处理。 */
    @Transactional
    public void submitDocument(long recordId, JwtUser actor) {
        long admissionId = documentAdmission(recordId);
        requireDoctorWrite(admissionId, actor);
        int updated = jdbc.update(
                "UPDATE medical_record SET status='SUBMITTED',submitted_at=NOW() WHERE record_id=? AND status='DRAFT'",
                recordId);
        if (updated == 0) {
            throw new BusinessException("只有草稿文书可以提交");
        }
        audit(recordId, "SUBMIT", "提交等待签名", actor.userId());
    }

    /** 签名将文书固定为不可改状态，后续内容变更必须产生新的版本。 */
    @Transactional
    public void signDocument(long recordId, String patientOpinion, JwtUser actor) {
        long admissionId = documentAdmission(recordId);
        requireDoctorWrite(admissionId, actor);
        int updated = jdbc.update(
                "UPDATE medical_record SET status='SIGNED',signed_at=NOW(),signed_by=?,patient_opinion=? "
                        + "WHERE record_id=? AND status='SUBMITTED'",
                actor.userId(),
                patientOpinion,
                recordId);
        if (updated == 0) {
            throw new BusinessException("只有已提交文书可以签名");
        }
        audit(recordId, "SIGN", "医师签名确认", actor.userId());
    }

    /** 已签名文书修订时复制为新草稿，原版本始终保留以供审计。 */
    @Transactional
    public long reviseDocument(long recordId, String reason, JwtUser actor) {
        Map<String, Object> original = jdbc.queryForMap(
                "SELECT * FROM medical_record WHERE record_id=? FOR UPDATE",
                recordId);
        long admissionId = ((Number) original.get("admission_id")).longValue();
        requireDoctorWrite(admissionId, actor);
        if (!"SIGNED".equals(original.get("status"))) {
            throw new BusinessException("只有已签名文书可以发起修订");
        }
        jdbc.update(
                "INSERT INTO medical_record(admission_id,record_type,document_code,title,template_name,content,"
                        + "content_json,recorded_by,status,version_no) VALUES (?,?,?,?,?,?,?,?, 'DRAFT',?)",
                admissionId,
                original.get("record_type"),
                original.get("document_code"),
                original.get("title"),
                original.get("template_name"),
                original.get("content"),
                original.get("content_json"),
                actor.userId(),
                ((Number) original.get("version_no")).intValue() + 1);
        long revisedRecordId = lastInsertId();
        jdbc.update(
                "INSERT INTO medical_record_revision(record_id,previous_record_id,revision_reason,revised_by) "
                        + "VALUES (?,?,?,?)",
                revisedRecordId,
                recordId,
                reason,
                actor.userId());
        audit(recordId, "REVISE", "已生成修订版本：" + revisedRecordId, actor.userId());
        audit(revisedRecordId, "CREATE_REVISION", reason, actor.userId());
        return revisedRecordId;
    }

    /** 作废仅允许未签名文书，避免已签名医疗记录被无痕删除。 */
    @Transactional
    public void voidDocument(long recordId, String reason, JwtUser actor) {
        if (reason == null || reason.isBlank()) {
            throw new BusinessException("作废文书必须填写原因");
        }
        long admissionId = documentAdmission(recordId);
        requireDoctorWrite(admissionId, actor);
        int updated = jdbc.update(
                "UPDATE medical_record SET status='VOID',void_reason=? WHERE record_id=? "
                        + "AND status IN ('DRAFT','SUBMITTED')",
                reason,
                recordId);
        if (updated == 0) {
            throw new BusinessException("仅草稿或待签文书可以作废");
        }
        audit(recordId, "VOID", reason, actor.userId());
    }

    /** 开立治疗或护理医嘱，护理医嘱由医师开立后交由护士执行。 */
    @Transactional
    public long createCareOrder(
            long admissionId,
            String orderType,
            String orderClass,
            String name,
            String dose,
            String route,
            String frequency,
            LocalDateTime startTime,
            LocalDateTime endTime,
            String instruction,
            JwtUser actor) {
        requireDoctorWrite(admissionId, actor);
        String orderNo = "CO" + NUMBER_TIME.format(LocalDateTime.now());
        jdbc.update(
                "INSERT INTO care_order(order_no,admission_id,order_type,order_class,order_name,dose,route,"
                        + "frequency,start_time,end_time,instruction_text,ordered_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                orderNo,
                admissionId,
                orderType,
                orderClass,
                name,
                dose,
                route,
                frequency,
                startTime,
                endTime,
                instruction,
                actor.userId());
        return lastInsertId();
    }

    /** 停止或取消医嘱必须加锁，避免护士执行与医生停止同时发生。 */
    @Transactional
    public void changeCareOrderStatus(long orderId, String action, String reason, JwtUser actor) {
        Map<String, Object> order = jdbc.queryForMap(
                "SELECT admission_id,status FROM care_order WHERE care_order_id=? FOR UPDATE",
                orderId);
        long admissionId = ((Number) order.get("admission_id")).longValue();
        requireDoctorWrite(admissionId, actor);
        if (!"OPEN".equals(order.get("status"))) {
            throw new BusinessException("只有执行中的医嘱可以停止或取消");
        }
        String status = "STOP".equals(action) ? "STOPPED" : "CANCELLED";
        jdbc.update(
                "UPDATE care_order SET status=?,stopped_by=?,stopped_at=NOW(),cancel_reason=? WHERE care_order_id=?",
                status,
                actor.userId(),
                reason,
                orderId);
    }

    /** 护士执行医嘱时在同一事务复核当前状态，再落执行人、时间和结果。 */
    @Transactional
    public void executeCareOrder(long orderId, String resultNote, JwtUser actor) {
        Map<String, Object> order = jdbc.queryForMap(
                "SELECT admission_id,status FROM care_order WHERE care_order_id=? FOR UPDATE",
                orderId);
        long admissionId = ((Number) order.get("admission_id")).longValue();
        requireNurseWrite(admissionId, actor);
        if (!"OPEN".equals(order.get("status"))) {
            throw new BusinessException("已停止或取消的医嘱不能执行");
        }
        jdbc.update(
                "INSERT INTO care_order_execution(care_order_id,executed_by,result_note) VALUES (?,?,?)",
                orderId,
                actor.userId(),
                resultNote);
    }

    /** 写入护士交班和成人护理记录，保留出入量与疼痛评分以支持护理汇总。 */
    @Transactional
    public long createNursingRecord(
            long admissionId,
            String recordType,
            String content,
            Integer painScore,
            java.math.BigDecimal intake,
            java.math.BigDecimal output,
            JwtUser actor) {
        requireNurseWrite(admissionId, actor);
        jdbc.update(
                "INSERT INTO nursing_record(admission_id,record_type,content,pain_score,intake_ml,output_ml,"
                        + "recorded_by) VALUES (?,?,?,?,?,?,?)",
                admissionId,
                recordType,
                content,
                painScore,
                intake,
                output,
                actor.userId());
        return lastInsertId();
    }

    /** 从路径模板复制任务到住院记录，路径任务与模板之后可独立推进。 */
    @Transactional
    public long enrollPathway(long admissionId, long templateId, JwtUser actor) {
        requireDoctorWrite(admissionId, actor);
        jdbc.update(
                "INSERT INTO clinical_pathway_enrollment(admission_id,pathway_template_id,enrolled_by) VALUES (?,?,?)",
                admissionId,
                templateId,
                actor.userId());
        long enrollmentId = lastInsertId();
        jdbc.update(
                "INSERT INTO clinical_pathway_task(enrollment_id,day_no,task_name,task_type) "
                        + "SELECT ?,day_no,task_name,task_type FROM clinical_pathway_task_template "
                        + "WHERE pathway_template_id=? ORDER BY sort_no",
                enrollmentId,
                templateId);
        return enrollmentId;
    }

    /** 完成路径任务或记录变异原因，状态不可从已完成回退。 */
    @Transactional
    public void completePathwayTask(long taskId, String variationReason, JwtUser actor) {
        Map<String, Object> task = jdbc.queryForMap(
                "SELECT e.admission_id,t.status FROM clinical_pathway_task t "
                        + "JOIN clinical_pathway_enrollment e ON e.enrollment_id=t.enrollment_id "
                        + "WHERE t.pathway_task_id=? FOR UPDATE",
                taskId);
        requireDoctorWrite(((Number) task.get("admission_id")).longValue(), actor);
        if (!"PENDING".equals(task.get("status"))) {
            throw new BusinessException("该路径任务已处理");
        }
        jdbc.update(
                "UPDATE clinical_pathway_task SET status='COMPLETED',completed_by=?,completed_at=NOW(),"
                        + "variation_reason=? WHERE pathway_task_id=?",
                actor.userId(),
                variationReason,
                taskId);
    }

    /** 创建疾病上报草稿，公共卫生平台对接外置，本系统只演示本地审核链路。 */
    @Transactional
    public long createDiseaseReport(long admissionId, String type, String diseaseName, String content, JwtUser actor) {
        requireDoctorWrite(admissionId, actor);
        jdbc.update(
                "INSERT INTO disease_report(admission_id,report_type,disease_name,report_content,reported_by) "
                        + "VALUES (?,?,?,?,?)",
                admissionId,
                type,
                diseaseName,
                content,
                actor.userId());
        return lastInsertId();
    }

    /** 医师提交上报草稿后交管理员审核，禁止直接跳过审核变为通过。 */
    @Transactional
    public void submitDiseaseReport(long reportId, JwtUser actor) {
        long admissionId = jdbc.queryForObject(
                "SELECT admission_id FROM disease_report WHERE disease_report_id=?",
                Long.class,
                reportId);
        requireDoctorWrite(admissionId, actor);
        int updated = jdbc.update(
                "UPDATE disease_report SET status='SUBMITTED',reported_at=NOW() "
                        + "WHERE disease_report_id=? AND status IN ('DRAFT','RETURNED')",
                reportId);
        if (updated == 0) {
            throw new BusinessException("只有草稿或退回的上报可以提交");
        }
    }

    /** 管理员审核疾病上报，退回需写入审核意见以便医生修改。 */
    @Transactional
    public void reviewDiseaseReport(long reportId, boolean approved, String note, JwtUser actor) {
        if (!"SUPER_ADMIN".equals(actor.roleCode())) {
            throw new BusinessException("疾病上报审核仅限最高管理员办理");
        }
        String status = jdbc.queryForObject(
                "SELECT status FROM disease_report WHERE disease_report_id=? FOR UPDATE",
                String.class,
                reportId);
        if (!"SUBMITTED".equals(status)) {
            throw new BusinessException("只有已提交的疾病上报可以审核");
        }
        if (!approved && (note == null || note.isBlank())) {
            throw new BusinessException("退回疾病上报必须填写意见");
        }
        jdbc.update(
                "UPDATE disease_report SET status=?,reviewed_by=?,reviewed_at=NOW(),review_note=? "
                        + "WHERE disease_report_id=?",
                approved ? "APPROVED" : "RETURNED",
                actor.userId(),
                note,
                reportId);
    }

    /** 记录 PDF 导出请求，模板未配置时明确返回可追踪的等待状态。 */
    @Transactional
    public long requestExport(long admissionId, String exportType, Long sourceId, JwtUser actor) {
        requireReadAccess(admissionId, actor);
        jdbc.update(
                "INSERT INTO export_task(admission_id,export_type,source_id,requested_by) VALUES (?,?,?,?)",
                admissionId,
                exportType,
                sourceId,
                actor.userId());
        return lastInsertId();
    }

    private long documentAdmission(long recordId) {
        return jdbc.queryForObject(
                "SELECT admission_id FROM medical_record WHERE record_id=?",
                Long.class,
                recordId);
    }

    private void audit(long recordId, String action, String detail, long actorId) {
        jdbc.update(
                "INSERT INTO medical_record_audit(record_id,action_type,action_detail,actor_id) VALUES (?,?,?,?)",
                recordId,
                action,
                detail,
                actorId);
    }

    private long lastInsertId() {
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }
}
