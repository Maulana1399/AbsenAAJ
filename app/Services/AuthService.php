<?php

namespace App\Services;

use App\Exceptions\ApiException;
use App\Models\User;
use Illuminate\Support\Facades\Hash;

class AuthService
{
    /**
     * Attempt to authenticate a user and issue a Sanctum token.
     *
     * @return array{user: User, token: string}
     */
    public function login(array $credentials): array
    {
        $user = User::query()
            ->where('email', $credentials['email'])
            ->first();

        if (! $user || ! Hash::check($credentials['password'], $user->password)) {
            throw new ApiException('Email atau password salah.', 'INVALID_CREDENTIALS', 401);
        }

        if (! $user->is_active) {
            throw new ApiException('Akun anda tidak aktif. Hubungi HR.', 'ACCOUNT_INACTIVE', 403);
        }

        $user->update(['last_login_at' => now()]);

        $user->loadMissing('employee');

        return [
            'user' => $user,
            'token' => $user->createToken('aaj-mobile')->plainTextToken,
        ];
    }

    public function logout(User $user): void
    {
        $user->currentAccessToken()?->delete();
    }
}
