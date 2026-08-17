package com.hospital.clinical;

import com.hospital.common.ApiResponse;
import com.hospital.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admissions/{admissionId}/clinical")
@PreAuthorize("hasAnyRole('DOCTOR','SUPER_ADMIN')")
/** 医师临床工作接口：所有写入都需先校验住院记录与责任医师。 */
public class ClinicalController {
    private final JdbcTemplate jdbc;
    private final ClinicalService service;

    public ClinicalController(JdbcTemplate jdbc, ClinicalService service) {
        this.jdbc = jdbc;
        this.service = service;
    }

    @GetMapping
    /** 聚合返回患者本次住院的核心临床记录，减少工作台首屏请求次数。 */
    public ApiResponse<Map<String, Object>> overview(@PathVariable long admissionId) {
        service.requireAccess(admissionId, CurrentUser.get());
        // 概览只读取本次住院记录，避免同一患者既往住院的临床资料混入当前工作台。
        List<Map<String, Object>> diagnoses = jdbc.queryForList(
                "SELECT * FROM diagnosis WHERE admission_id=? AND status='ACTIVE'",
                admissionId);
        List<Map<String, Object>> records = jdbc.queryForList(
                "SELECT * FROM medical_record WHERE admission_id=? ORDER BY recorded_at DESC",
                admissionId);
        List<Map<String, Object>> prescriptions = jdbc.queryForList(
                "SELECT * FROM prescription WHERE admission_id=? ORDER BY ordered_at DESC",
                admissionId);
        List<Map<String, Object>> examOrders = jdbc.queryForList(
                "SELECT * FROM exam_order WHERE admission_id=? ORDER BY ordered_at DESC",
                admissionId);
        List<Map<String, Object>> vitalSigns = jdbc.queryForList(
                "SELECT * FROM vital_sign WHERE admission_id=? ORDER BY measured_at DESC LIMIT 50",
                admissionId);
        return ApiResponse.ok(Map.of(
                "diagnoses", diagnoses,
                "records", records,
                "prescriptions", prescriptions,
                "examOrders", examOrders,
                "vitalSigns", vitalSigns));
    }

    /** 查询单张检查单及其项目，用于医师按项目录入检查报告。 */
    @GetMapping("/exam-orders/{orderId}")
    public ApiResponse<Map<String, Object>> examOrderDetail(
            @PathVariable long admissionId,
            @PathVariable long orderId) {
        service.requireAccess(admissionId, CurrentUser.get());
        Map<String, Object> order = jdbc.queryForMap(
                "SELECT * FROM exam_order WHERE exam_order_id=? AND admission_id=?",
                orderId,
                admissionId);
        List<Map<String, Object>> items = jdbc.queryForList(
                "SELECT eoi.*,ei.item_name,ei.item_type,er.report_id,er.report_name,er.status AS report_status "
                        + "FROM exam_order_item eoi "
                        + "JOIN exam_item ei ON ei.exam_item_id=eoi.exam_item_id "
                        + "LEFT JOIN exam_report er ON er.exam_order_item_id=eoi.exam_order_item_id "
                        + "WHERE eoi.exam_order_id=? ORDER BY eoi.exam_order_item_id",
                orderId);
        return ApiResponse.ok(Map.of("order", order, "items", items));
    }

    @PostMapping("/diagnoses")
    /** 新增入院、主要或出院诊断。 */
    public ApiResponse<Void> diagnosis(
            @PathVariable long admissionId,
            @Valid @RequestBody DiagnosisRequest request) {
        service.requireAccess(admissionId, CurrentUser.get());
        // 诊断人取自安全上下文，不能由请求体指定，防止伪造临床记录责任人。
        jdbc.update(
                "INSERT INTO diagnosis(admission_id,diagnosis_code,diagnosis_name,diagnosis_type,is_primary,"
                        + "diagnosed_by) VALUES (?,?,?,?,?,?)",
                admissionId,
                request.code(),
                request.name(),
                request.type(),
                request.primary(),
                CurrentUser.get().userId());
        return ApiResponse.ok(null);
    }

    @PostMapping("/records")
    /** 保存病程记录草稿，后续可按状态进入签名流程。 */
    public ApiResponse<Void> record(
            @PathVariable long admissionId,
            @Valid @RequestBody MedicalRecordRequest request) {
        service.requireAccess(admissionId, CurrentUser.get());
        // 新建文书统一从草稿开始，签名流程不会被接口创建动作绕过。
        jdbc.update(
                "INSERT INTO medical_record(admission_id,record_type,title,content,recorded_by,status) "
                        + "VALUES (?,?,?,?,?,'DRAFT')",
                admissionId,
                request.type(),
                request.title(),
                request.content(),
                CurrentUser.get().userId());
        return ApiResponse.ok(null);
    }

    @PostMapping("/assessments")
    /** 录入住院护理风险或生活能力评估。 */
    public ApiResponse<Void> assessment(
            @PathVariable long admissionId,
            @Valid @RequestBody AssessmentRequest request) {
        service.requireAccess(admissionId, CurrentUser.get());
        // 评估人同样固定为当前登录医师，保证护理记录可审计。
        jdbc.update(
                "INSERT INTO nursing_assessment(admission_id,assessment_type,score,risk_level,measures,"
                        + "assessed_by,remark) VALUES (?,?,?,?,?,?,?)",
                admissionId,
                request.type(),
                request.score(),
                request.riskLevel(),
                request.measures(),
                CurrentUser.get().userId(),
                request.remark());
        return ApiResponse.ok(null);
    }

    @PostMapping("/vital-signs")
    /** 记录一次生命体征测量结果。 */
    public ApiResponse<Void> vital(
            @PathVariable long admissionId,
            @Valid @RequestBody VitalSignRequest request) {
        service.requireAccess(admissionId, CurrentUser.get());
        // 测量时刻由请求明确提供，支持补录历史体征而不误用服务器写入时间。
        jdbc.update(
                "INSERT INTO vital_sign(admission_id,measured_at,temperature,pulse,respiratory_rate,"
                        + "systolic_bp,diastolic_bp,spo2,measured_by,remark) VALUES (?,?,?,?,?,?,?,?,?,?)",
                admissionId,
                request.measuredAt(),
                request.temperature(),
                request.pulse(),
                request.respiratoryRate(),
                request.systolicBp(),
                request.diastolicBp(),
                request.spo2(),
                CurrentUser.get().userId(),
                request.remark());
        return ApiResponse.ok(null);
    }

    @PostMapping("/prescriptions")
    /** 开立处方；服务层同时生成不可受后续调价影响的费用快照。 */
    public ApiResponse<Map<String, Long>> prescription(
            @PathVariable long admissionId,
            @Valid @RequestBody PrescriptionRequest request) {
        long prescriptionId = service.createPrescription(
                admissionId,
                request.type(),
                request.startTime(),
                request.endTime(),
                request.remark(),
                request.items(),
                CurrentUser.get());
        return ApiResponse.ok(Map.of("prescriptionId", prescriptionId));
    }

    @PostMapping("/exam-orders")
    /** 开立检查检验项目；每个项目独立生成执行状态和费用。 */
    public ApiResponse<Map<String, Long>> examOrder(
            @PathVariable long admissionId,
            @Valid @RequestBody ExamOrderRequest request) {
        long examOrderId = service.createExamOrder(
                admissionId,
                request.priority(),
                request.clinicalNote(),
                request.examItemIds(),
                CurrentUser.get());
        return ApiResponse.ok(Map.of("examOrderId", examOrderId));
    }

    @PostMapping("/exam-order-items/{itemId}/report")
    /** 发布项目报告并推动检查单状态至部分完成或全部完成。 */
    public ApiResponse<Void> report(
            @PathVariable long admissionId,
            @PathVariable long itemId,
            @Valid @RequestBody ReportRequest request) {
        service.publishReport(
                itemId,
                request.reportName(),
                request.conclusion(),
                request.results(),
                CurrentUser.get());
        return ApiResponse.ok(null);
    }

    /** 诊断录入参数，primary 指示该次住院统计使用的主要诊断。 */
    public record DiagnosisRequest(
            String code,
            @NotBlank String name,
            @NotBlank String type,
            boolean primary) {
    }

    /** 病程文书草稿参数，正文、标题和文书类型均为必填。 */
    public record MedicalRecordRequest(
            @NotBlank String type,
            @NotBlank String title,
            @NotBlank String content) {
    }

    /** 护理评估参数，分值和风险等级可按不同评估量表选择填写。 */
    public record AssessmentRequest(
            @NotBlank String type,
            BigDecimal score,
            String riskLevel,
            String measures,
            String remark) {
    }

    /** 生命体征参数，允许按实际采集项目选择性提交数值。 */
    public record VitalSignRequest(
            @NotNull LocalDateTime measuredAt,
            BigDecimal temperature,
            Integer pulse,
            Integer respiratoryRate,
            Integer systolicBp,
            Integer diastolicBp,
            BigDecimal spo2,
            String remark) {
    }

    /** 处方主信息及至少一条药品明细，服务层据此生成费用快照。 */
    public record PrescriptionRequest(
            @NotBlank String type,
            LocalDateTime startTime,
            LocalDateTime endTime,
            String remark,
            @NotNull List<@Valid PrescriptionItemRequest> items) {
    }

    /** 单个处方药品的剂量、频次、疗程和开立数量。 */
    public record PrescriptionItemRequest(
            @NotNull Long drugId,
            @NotNull @DecimalMin("0.01") BigDecimal dose,
            @NotBlank String doseUnit,
            @NotBlank String route,
            @NotBlank String frequency,
            @NotNull Integer days,
            @NotNull Integer quantity,
            String instruction) {
    }

    /** 检查单参数，多个项目共享临床说明和优先级。 */
    public record ExamOrderRequest(
            @NotBlank String priority,
            String clinicalNote,
            @NotNull List<Long> examItemIds) {
    }

    /** 项目报告参数，报告主结论与逐项结果分开保存。 */
    public record ReportRequest(
            @NotBlank String reportName,
            String conclusion,
            @NotNull List<@Valid ResultRequest> results) {
    }

    /** 单条检查或检验结果，sortNo 用于稳定输出报告项目顺序。 */
    public record ResultRequest(
            @NotBlank String itemName,
            String qualitativeValue,
            BigDecimal quantitativeValue,
            String unit,
            String referenceRange,
            String abnormalFlag,
            String remark,
            @NotNull Integer sortNo) {
    }
}
