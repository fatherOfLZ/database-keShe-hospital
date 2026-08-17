package com.hospital.common;

import jakarta.validation.ConstraintViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/** 集中处理参数校验、业务冲突和未预期错误，保持 API 响应结构一致。 */
@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(BusinessException.class)
    ResponseEntity<ApiResponse<Void>> business(BusinessException exception) {
        // 业务冲突不属于服务故障，调用方可以根据提示调整操作后重试。
        return ResponseEntity.status(HttpStatus.CONFLICT).body(ApiResponse.error(409, exception.getMessage()));
    }

    @ExceptionHandler({
            MethodArgumentNotValidException.class,
            ConstraintViolationException.class,
            IllegalArgumentException.class
    })
    ResponseEntity<ApiResponse<Void>> validation(Exception exception) {
        // 请求字段不合法时返回 400，避免将校验问题误报为服务器错误。
        return ResponseEntity.badRequest().body(ApiResponse.error(400, exception.getMessage()));
    }

    @ExceptionHandler(AccessDeniedException.class)
    ResponseEntity<ApiResponse<Void>> denied() {
        // 方法级权限校验失败后统一转换为 403。
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(ApiResponse.error(403, "没有权限执行此操作"));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ApiResponse<Void>> unknown(Exception exception) {
        // 不向客户端暴露内部异常栈，避免泄露实现细节。
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(ApiResponse.error(500, "系统内部错误"));
    }
}
