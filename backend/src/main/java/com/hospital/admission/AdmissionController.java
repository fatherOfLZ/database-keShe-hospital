package com.hospital.admission;

import com.hospital.common.ApiResponse;
import com.hospital.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admissions")
/** 住院处业务接口：负责患者住院期间的行政流程。 */
public class AdmissionController {
    private final JdbcTemplate jdbc;
    private final AdmissionService service;

    public AdmissionController(JdbcTemplate jdbc, AdmissionService service) {
        this.jdbc = jdbc;
        this.service = service;
    }

    @GetMapping
    /** 按住院状态查询患者列表，供住院处和医师选择在院患者。 */
    public ApiResponse<List<Map<String, Object>>> list(
            @RequestParam(defaultValue = "IN_HOSPITAL") String status) {
        // 列表拼接患者、科室、床位和责任医师信息，满足住院工作台的一次性展示需求。
        String sql = "SELECT a.*,p.name AS patient_name,p.gender,p.phone,d.department_name,b.bed_no,"
                + "u.real_name AS doctor_name FROM admission a "
                + "JOIN patient p ON p.patient_id=a.patient_id "
                + "JOIN department d ON d.department_id=a.current_department_id "
                + "LEFT JOIN bed b ON b.bed_id=a.current_bed_id "
                + "LEFT JOIN system_user u ON u.user_id=a.attending_doctor_id "
                + "WHERE a.status=? ORDER BY a.admission_time DESC";
        return ApiResponse.ok(jdbc.queryForList(sql, status));
    }

    /** 返回启用科室，供入院登记和转科申请选择目标科室。 */
    @GetMapping("/departments")
    @PreAuthorize("hasAnyRole('DOCTOR','ADMISSION','SUPER_ADMIN')")
    public ApiResponse<List<Map<String, Object>>> availableDepartments() {
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT department_id,department_code,department_name,department_type "
                        + "FROM department WHERE status='ACTIVE' ORDER BY department_code"));
    }

    /** 返回指定科室当前可分配床位，住院处和医师均无需知道床位主键。 */
    @GetMapping("/available-beds")
    @PreAuthorize("hasAnyRole('DOCTOR','ADMISSION','SUPER_ADMIN')")
    public ApiResponse<List<Map<String, Object>>> availableBeds(@RequestParam long departmentId) {
        String sql = "SELECT b.bed_id,b.bed_no,b.bed_type,b.nursing_level,w.ward_name "
                + "FROM bed b JOIN ward w ON w.ward_id=b.ward_id "
                + "WHERE w.department_id=? AND b.status='AVAILABLE' "
                + "ORDER BY w.ward_code,b.bed_no";
        return ApiResponse.ok(jdbc.queryForList(sql, departmentId));
    }

    /** 返回可作为责任医师的启用账号，避免入院登记界面手工填写用户编号。 */
    @GetMapping("/doctors")
    @PreAuthorize("hasAnyRole('ADMISSION','SUPER_ADMIN')")
    public ApiResponse<List<Map<String, Object>>> doctors() {
        String sql = "SELECT u.user_id,u.real_name,u.employee_no,u.department_id,d.department_name "
                + "FROM system_user u JOIN role r ON r.role_id=u.role_id "
                + "LEFT JOIN department d ON d.department_id=u.department_id "
                + "WHERE r.role_code='DOCTOR' AND u.status='ACTIVE' ORDER BY u.real_name";
        return ApiResponse.ok(jdbc.queryForList(sql));
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('ADMISSION','SUPER_ADMIN')")
    /** 办理入院登记，同时由服务层占用所选床位。 */
    public ApiResponse<Map<String, Long>> admit(@Valid @RequestBody AdmitRequest request) {
        long admissionId = service.admit(
                request.patientId(),
                request.departmentId(),
                request.doctorId(),
                request.bedId(),
                request.nursingLevel(),
                request.feeType(),
                request.insuranceType(),
                CurrentUser.get());
        return ApiResponse.ok(Map.of("admissionId", admissionId));
    }

    @GetMapping("/{id}")
    /** 查询单次住院详情及其押金、转科历史。 */
    public ApiResponse<Map<String, Object>> detail(@PathVariable long id) {
        // 详情同时返回主记录、资金流水和转科历史，避免前端自行拼接多类业务数据。
        String admissionSql = "SELECT a.*,p.name AS patient_name,p.gender,p.birth_date,p.phone,"
                + "d.department_name,b.bed_no FROM admission a "
                + "JOIN patient p ON p.patient_id=a.patient_id "
                + "JOIN department d ON d.department_id=a.current_department_id "
                + "LEFT JOIN bed b ON b.bed_id=a.current_bed_id WHERE a.admission_id=?";
        Map<String, Object> admission = jdbc.queryForMap(admissionSql, id);
        List<Map<String, Object>> deposits = jdbc.queryForList(
                "SELECT * FROM deposit_transaction WHERE admission_id=? ORDER BY txn_time DESC",
                id);
        List<Map<String, Object>> transfers = jdbc.queryForList(
                "SELECT * FROM department_transfer WHERE admission_id=? ORDER BY request_time DESC",
                id);
        return ApiResponse.ok(Map.of(
                "admission", admission,
                "deposits", deposits,
                "transfers", transfers));
    }

    @PostMapping("/{id}/deposits")
    @PreAuthorize("hasAnyRole('ADMISSION','SUPER_ADMIN')")
    /** 记录押金缴纳、退款或冲正流水。 */
    public ApiResponse<Void> deposit(
            @PathVariable long id,
            @Valid @RequestBody DepositRequest request) {
        service.deposit(
                id,
                request.type(),
                request.amount(),
                request.paymentMethod(),
                request.remark(),
                CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @PostMapping("/{id}/transfers")
    @PreAuthorize("hasAnyRole('DOCTOR','ADMISSION','SUPER_ADMIN')")
    /** 创建待住院处确认的转科申请。 */
    public ApiResponse<Map<String, Long>> requestTransfer(
            @PathVariable long id,
            @Valid @RequestBody TransferRequest request) {
        long transferId = service.requestTransfer(
                id,
                request.toDepartmentId(),
                request.toBedId(),
                request.reason(),
                CurrentUser.get());
        return ApiResponse.ok(Map.of("transferId", transferId));
    }

    @PostMapping("/transfers/{transferId}/approve")
    @PreAuthorize("hasAnyRole('ADMISSION','SUPER_ADMIN')")
    /** 确认转科，并由服务层原子地更新床位与当前科室。 */
    public ApiResponse<Void> approveTransfer(@PathVariable long transferId) {
        service.approveTransfer(transferId, CurrentUser.get());
        return ApiResponse.ok(null);
    }

    @PostMapping("/{id}/settlement")
    @PreAuthorize("hasAnyRole('ADMISSION','SUPER_ADMIN')")
    /** 执行最终费用结算、退款和出院。 */
    public ApiResponse<Map<String, BigDecimal>> settlement(@PathVariable long id) {
        return ApiResponse.ok(service.settle(id, CurrentUser.get()));
    }

    /** 入院登记参数，床位和患者为必填，责任医师可由住院处按实际情况暂不指定。 */
    public record AdmitRequest(
            @NotNull Long patientId,
            @NotNull Long departmentId,
            Long doctorId,
            @NotNull Long bedId,
            @NotBlank String nursingLevel,
            @NotBlank String feeType,
            String insuranceType) {
    }

    /** 押金操作参数，金额必须为正数以避免以负数绕开收退规则。 */
    public record DepositRequest(
            @NotBlank String type,
            @NotNull @DecimalMin("0.01") BigDecimal amount,
            @NotBlank String paymentMethod,
            String remark) {
    }

    /** 转科申请参数，目标科室、床位和申请理由均需留存。 */
    public record TransferRequest(
            @NotNull Long toDepartmentId,
            @NotNull Long toBedId,
            @NotBlank String reason) {
    }
}
