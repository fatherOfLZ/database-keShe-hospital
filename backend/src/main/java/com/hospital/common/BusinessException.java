package com.hospital.common;

/** 表示可预期的业务冲突，由全局异常处理器转换为 409 响应。 */
public class BusinessException extends RuntimeException {
    public BusinessException(String message) {
        // message 会作为可处理的业务提示返回给调用端，因此由各业务规则提供明确原因。
        super(message);
    }
}
