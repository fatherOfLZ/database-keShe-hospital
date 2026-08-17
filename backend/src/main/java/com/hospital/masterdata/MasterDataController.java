package com.hospital.masterdata;

import com.hospital.common.ApiResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/master-data")
@PreAuthorize("hasRole('SUPER_ADMIN')")
/** 最高管理员维护的基础目录与系统账号接口。 */
public class MasterDataController {
    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwordEncoder;

    public MasterDataController(JdbcTemplate jdbc, PasswordEncoder passwordEncoder) {
        this.jdbc = jdbc;
        this.passwordEncoder = passwordEncoder;
    }

    @GetMapping("/departments")
    /** 查询全部科室及启用状态。 */
    public ApiResponse<List<Map<String, Object>>> departments() {
        return ApiResponse.ok(jdbc.queryForList("SELECT * FROM department ORDER BY department_code"));
    }

    @PostMapping("/departments")
    /** 新增科室目录项。 */
    public ApiResponse<Void> createDepartment(@Valid @RequestBody DepartmentRequest request) {
        jdbc.update(
                "INSERT INTO department(department_code,department_name,department_type,phone) VALUES (?,?,?,?)",
                request.code(),
                request.name(),
                request.type(),
                request.phone());
        return ApiResponse.ok(null);
    }

    @PutMapping("/departments/{id}/status")
    /** 启用或停用科室，不删除已有业务引用。 */
    public ApiResponse<Void> setDepartmentStatus(@PathVariable long id, @RequestParam String status) {
        jdbc.update("UPDATE department SET status=? WHERE department_id=?", status, id);
        return ApiResponse.ok(null);
    }

    @GetMapping("/wards")
    /** 查询病区及其所属科室。 */
    public ApiResponse<List<Map<String, Object>>> wards() {
        // 列表连带返回所属科室名称，前端无需再为每个病区单独查询科室。
        String sql = "SELECT w.*,d.department_name FROM ward w "
                + "JOIN department d ON d.department_id=w.department_id ORDER BY w.ward_code";
        return ApiResponse.ok(jdbc.queryForList(sql));
    }

    @PostMapping("/wards")
    /** 新增病区。 */
    public ApiResponse<Void> createWard(@Valid @RequestBody WardRequest request) {
        jdbc.update(
                "INSERT INTO ward(department_id,ward_code,ward_name,floor_no) VALUES (?,?,?,?)",
                request.departmentId(),
                request.code(),
                request.name(),
                request.floorNo());
        return ApiResponse.ok(null);
    }

    @GetMapping("/beds")
    /** 查询床位、病区与科室的当前关联。 */
    public ApiResponse<List<Map<String, Object>>> beds() {
        // 床位归属经过病区关联到科室，用于管理员核对物理位置和床位状态。
        String sql = "SELECT b.*,w.ward_name,d.department_name FROM bed b "
                + "JOIN ward w ON w.ward_id=b.ward_id "
                + "JOIN department d ON d.department_id=w.department_id "
                + "ORDER BY w.ward_code,b.bed_no";
        return ApiResponse.ok(jdbc.queryForList(sql));
    }

    @PostMapping("/beds")
    /** 新增可供住院流程分配的床位。 */
    public ApiResponse<Void> createBed(@Valid @RequestBody BedRequest request) {
        jdbc.update(
                "INSERT INTO bed(ward_id,bed_no,bed_type,nursing_level) VALUES (?,?,?,?)",
                request.wardId(),
                request.bedNo(),
                request.bedType(),
                request.nursingLevel());
        return ApiResponse.ok(null);
    }

    @PutMapping("/beds/{id}/status")
    /** 维护未占用床位的启用状态。 */
    public ApiResponse<Void> setBedStatus(@PathVariable long id, @RequestParam String status) {
        // 已占用床位只能通过转科或出院流程释放，不能被基础资料维护直接覆盖。
        jdbc.update("UPDATE bed SET status=? WHERE bed_id=? AND status<>'OCCUPIED'", status, id);
        return ApiResponse.ok(null);
    }

    @GetMapping("/drugs")
    /** 查询可开立的药品目录。 */
    public ApiResponse<List<Map<String, Object>>> drugs() {
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT * FROM drug WHERE status='ACTIVE' ORDER BY drug_code"));
    }

    @PostMapping("/drugs")
    /** 新增药品及其当前目录价格。 */
    public ApiResponse<Void> createDrug(@Valid @RequestBody DrugRequest request) {
        jdbc.update(
                "INSERT INTO drug(drug_code,drug_name,generic_name,specification,dosage_form,unit,unit_price,"
                        + "stock_qty) VALUES (?,?,?,?,?,?,?,?)",
                request.code(),
                request.name(),
                request.genericName(),
                request.specification(),
                request.dosageForm(),
                request.unit(),
                request.unitPrice(),
                request.stockQty());
        return ApiResponse.ok(null);
    }

    @GetMapping("/exam-items")
    /** 查询可开立的检查检验项目。 */
    public ApiResponse<List<Map<String, Object>>> examItems() {
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT * FROM exam_item WHERE status='ACTIVE' ORDER BY item_code"));
    }

    @PostMapping("/exam-items")
    /** 新增检查检验项目及执行科室。 */
    public ApiResponse<Void> createExamItem(@Valid @RequestBody ExamItemRequest request) {
        jdbc.update(
                "INSERT INTO exam_item(item_code,item_name,item_type,department_id,unit,reference_range,"
                        + "unit_price) VALUES (?,?,?,?,?,?,?)",
                request.code(),
                request.name(),
                request.type(),
                request.departmentId(),
                request.unit(),
                request.referenceRange(),
                request.unitPrice());
        return ApiResponse.ok(null);
    }

    @GetMapping("/users")
    /** 查询系统账号及角色、科室归属。 */
    public ApiResponse<List<Map<String, Object>>> users() {
        // 密码哈希绝不返回给客户端，只返回账号管理页面实际需要的身份和归属字段。
        String sql = "SELECT u.user_id,u.username,u.real_name,u.employee_no,u.license_no,u.status,"
                + "r.role_code,d.department_name FROM system_user u "
                + "JOIN role r ON r.role_id=u.role_id "
                + "LEFT JOIN department d ON d.department_id=u.department_id ORDER BY u.user_id";
        return ApiResponse.ok(jdbc.queryForList(sql));
    }

    @PostMapping("/users")
    /** 创建系统账号，并在写入前使用 BCrypt 哈希密码。 */
    public ApiResponse<Void> createUser(@Valid @RequestBody UserRequest request) {
        // 密码仅以 BCrypt 哈希写入数据库，原始密码不会被持久化或返回。
        jdbc.update(
                "INSERT INTO system_user(role_id,department_id,username,password_hash,real_name,employee_no,"
                        + "license_no,phone) VALUES (?,?,?,?,?,?,?,?)",
                request.roleId(),
                request.departmentId(),
                request.username(),
                passwordEncoder.encode(request.password()),
                request.realName(),
                request.employeeNo(),
                request.licenseNo(),
                request.phone());
        return ApiResponse.ok(null);
    }

    /** 新增科室时接收的目录字段，编码承担科室的业务唯一标识。 */
    public record DepartmentRequest(
            @NotBlank String code,
            @NotBlank String name,
            @NotBlank String type,
            String phone) {
    }

    /** 新增病区时接收的所属科室和物理位置字段。 */
    public record WardRequest(
            @NotNull Long departmentId,
            @NotBlank String code,
            @NotBlank String name,
            String floorNo) {
    }

    /** 新增床位时接收的病区归属及护理能力字段。 */
    public record BedRequest(
            @NotNull Long wardId,
            @NotBlank String bedNo,
            @NotBlank String bedType,
            @NotBlank String nursingLevel) {
    }

    /** 新增药品目录时接收的规格、单位、目录价格和演示库存字段。 */
    public record DrugRequest(
            @NotBlank String code,
            @NotBlank String name,
            String genericName,
            String specification,
            String dosageForm,
            @NotBlank String unit,
            @NotNull @DecimalMin("0") BigDecimal unitPrice,
            @NotNull Integer stockQty) {
    }

    /** 新增检查检验目录时接收的执行科室、参考范围和当前价格。 */
    public record ExamItemRequest(
            @NotBlank String code,
            @NotBlank String name,
            @NotBlank String type,
            Long departmentId,
            String unit,
            String referenceRange,
            @NotNull @DecimalMin("0") BigDecimal unitPrice) {
    }

    /** 新建系统账号时接收的角色、科室归属和身份资料。 */
    public record UserRequest(
            @NotNull Long roleId,
            Long departmentId,
            @NotBlank String username,
            @NotBlank String password,
            @NotBlank String realName,
            String employeeNo,
            String licenseNo,
            String phone) {
    }
}
