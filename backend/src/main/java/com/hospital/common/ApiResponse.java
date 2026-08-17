package com.hospital.common;

/** 所有 REST 接口共用的响应结构：业务码、提示语和数据主体。 */
public record ApiResponse<T>(int code, String message, T data) {
    public static <T> ApiResponse<T> ok(T data) {
        // 业务执行成功时统一使用 0 作为成功码。
        return new ApiResponse<>(0, "OK", data);
    }

    public static <T> ApiResponse<T> error(int code, String message) {
        // 错误响应没有数据主体，调用方只需处理错误码和提示信息。
        return new ApiResponse<>(code, message, null);
    }
}
