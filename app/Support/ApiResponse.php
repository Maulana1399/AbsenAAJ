<?php

namespace App\Support;

use Illuminate\Http\JsonResponse;

final class ApiResponse
{
    public static function success(mixed $data = [], int $status = 200): JsonResponse
    {
        return response()->json(['data' => $data], $status);
    }

    public static function error(string $message, string $code, int $status = 400): JsonResponse
    {
        return response()->json([
            'message' => $message,
            'code' => $code,
        ], $status);
    }

    public static function validation(array $errors): JsonResponse
    {
        return response()->json([
            'message' => 'Data tidak valid.',
            'code' => 'VALIDATION_ERROR',
            'errors' => $errors,
        ], 422);
    }
}
