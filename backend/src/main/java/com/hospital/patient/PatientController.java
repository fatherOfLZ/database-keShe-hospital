package com.hospital.patient;

import com.hospital.common.ApiResponse;
import com.hospital.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/patients")
/** 患者主数据与过敏史接口。 */
public class PatientController {
    private final JdbcTemplate jdbc;

    public PatientController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping
    /** 按姓名、院内编号或身份证号分页检索患者。 */
    public ApiResponse<Map<String, Object>> list(
            @RequestParam(defaultValue = "") String keyword,
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int pageSize) {
        // 限制单页最大数量，防止演示系统因一次检索过多患者影响响应速度。
        int size = Math.min(Math.max(pageSize, 1), 100);
        int offset = Math.max(page - 1, 0) * size;
        String like = "%" + keyword + "%";
        String filter = "patient_no LIKE ? OR name LIKE ? OR id_card_no LIKE ?";

        List<Map<String, Object>> items = jdbc.queryForList(
                "SELECT * FROM patient WHERE " + filter + " ORDER BY patient_id DESC LIMIT ? OFFSET ?",
                like,
                like,
                like,
                size,
                offset);
        Long total = jdbc.queryForObject(
                "SELECT COUNT(*) FROM patient WHERE " + filter,
                Long.class,
                like,
                like,
                like);
        return ApiResponse.ok(Map.of(
                "items", items,
                "page", page,
                "pageSize", size,
                "total", total));
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('ADMISSION','SUPER_ADMIN')")
    /** 由住院处创建可复用的患者主档案。 */
    public ApiResponse<Map<String, Object>> create(@Valid @RequestBody PatientRequest request) {
        // 患者编号由服务端生成，避免住院处手工录入造成重复或冲突。
        String patientNo = "P" + System.currentTimeMillis();
        jdbc.update(
                "INSERT INTO patient(patient_no,name,id_card_no,gender,birth_date,height_cm,weight_kg,phone,"
                        + "id_type,nationality,occupation,marital_status,birth_place,registered_address,current_address,"
                        + "address,postal_code,emergency_contact_name,emergency_contact_relation,emergency_contact_phone) "
                        + "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                patientNo,
                request.name(),
                request.idCardNo(),
                request.gender(),
                request.birthDate(),
                request.heightCm(),
                request.weightKg(),
                request.phone(),
                request.idType() == null || request.idType().isBlank() ? "ID_CARD" : request.idType(),
                request.nationality(),
                request.occupation(),
                request.maritalStatus(),
                request.birthPlace(),
                request.registeredAddress(),
                request.currentAddress(),
                request.address(),
                request.postalCode(),
                request.emergencyContactName(),
                request.emergencyContactRelation(),
                request.emergencyContactPhone());
        long patientId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        return ApiResponse.ok(Map.of("patientId", patientId, "patientNo", patientNo));
    }

    @GetMapping("/{id}")
    /** 查询患者基本信息和可追溯的过敏史。 */
    public ApiResponse<Map<String, Object>> detail(@PathVariable long id) {
        // 过敏史同时带回记录人姓名，使临床人员能判断信息来源。
        Map<String, Object> patient = jdbc.queryForMap("SELECT * FROM patient WHERE patient_id=?", id);
        List<Map<String, Object>> allergies = jdbc.queryForList(
                "SELECT a.*,u.real_name AS recorder_name FROM patient_allergy a "
                        + "JOIN system_user u ON u.user_id=a.recorded_by "
                        + "WHERE patient_id=? ORDER BY recorded_at DESC",
                id);
        return ApiResponse.ok(Map.of("patient", patient, "allergies", allergies));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAnyRole('ADMISSION','SUPER_ADMIN')")
    /** 更新主档中经常由住院处补录的联系、地址和职业等资料，不影响历史住院记录。 */
    public ApiResponse<Void> update(@PathVariable long id, @Valid @RequestBody PatientRequest request) {
        jdbc.update(
                "UPDATE patient SET name=?,id_card_no=?,gender=?,birth_date=?,height_cm=?,weight_kg=?,phone=?,"
                        + "id_type=?,nationality=?,occupation=?,marital_status=?,birth_place=?,registered_address=?,"
                        + "current_address=?,address=?,postal_code=?,emergency_contact_name=?,"
                        + "emergency_contact_relation=?,emergency_contact_phone=? WHERE patient_id=?",
                request.name(),
                request.idCardNo(),
                request.gender(),
                request.birthDate(),
                request.heightCm(),
                request.weightKg(),
                request.phone(),
                request.idType() == null || request.idType().isBlank() ? "ID_CARD" : request.idType(),
                request.nationality(),
                request.occupation(),
                request.maritalStatus(),
                request.birthPlace(),
                request.registeredAddress(),
                request.currentAddress(),
                request.address(),
                request.postalCode(),
                request.emergencyContactName(),
                request.emergencyContactRelation(),
                request.emergencyContactPhone(),
                id);
        return ApiResponse.ok(null);
    }

    @PostMapping("/{id}/allergies")
    @PreAuthorize("hasAnyRole('DOCTOR','SUPER_ADMIN')")
    /** 记录医生确认的药物、食物或其他过敏信息。 */
    public ApiResponse<Void> addAllergy(
            @PathVariable long id,
            @Valid @RequestBody AllergyRequest request) {
        jdbc.update(
                "INSERT INTO patient_allergy(patient_id,allergen_name,allergy_type,result,reaction_text,"
                        + "severity,recorded_by,remark) VALUES (?,?,?,?,?,?,?,?)",
                id,
                request.allergenName(),
                request.allergyType(),
                request.result(),
                request.reaction(),
                request.severity(),
                CurrentUser.get().userId(),
                request.remark());
        return ApiResponse.ok(null);
    }

    /** 患者建档参数，保留紧急联系人以支撑住院期间的实际联系需求。 */
    public record PatientRequest(
            @NotBlank String name,
            String idCardNo,
            @NotBlank String gender,
            @NotNull LocalDate birthDate,
            BigDecimal heightCm,
            BigDecimal weightKg,
            String phone,
            String idType,
            String nationality,
            String occupation,
            String maritalStatus,
            String birthPlace,
            String registeredAddress,
            String currentAddress,
            String address,
            String postalCode,
            String emergencyContactName,
            String emergencyContactRelation,
            String emergencyContactPhone) {
    }

    /** 过敏史参数，结果、严重程度和反应描述用于临床风险提示。 */
    public record AllergyRequest(
            @NotBlank String allergenName,
            @NotBlank String allergyType,
            @NotBlank String result,
            String reaction,
            String severity,
            String remark) {
    }
}
