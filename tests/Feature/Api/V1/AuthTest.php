<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    private function makeUser(array $attributes = []): User
    {
        return User::factory()->create(array_merge([
            'email' => 'employee@example.com',
            'password' => 'secret-password',
        ], $attributes));
    }

    private function credentials(array $overrides = []): array
    {
        return array_merge([
            'email' => 'employee@example.com',
            'password' => 'secret-password',
        ], $overrides);
    }

    public function test_login_succeeds_and_returns_user_and_token(): void
    {
        $user = $this->makeUser(['role' => UserRole::EMPLOYEE]);

        $response = $this->postJson('/api/v1/auth/login', $this->credentials());

        $response->assertOk()
            ->assertJsonStructure([
                'data' => [
                    'user' => ['id', 'name', 'email', 'role', 'is_active'],
                    'token',
                ],
            ]);

        $token = $response->json('data.token');
        $this->assertNotNull($token);

        $this->assertDatabaseCount('personal_access_tokens', 1);
        $this->assertNotNull($user->fresh()->last_login_at);
        $this->assertSame($user->id, $response->json('data.user.id'));
    }

    public function test_login_fails_with_wrong_password(): void
    {
        $this->makeUser();

        $response = $this->postJson('/api/v1/auth/login', $this->credentials([
            'password' => 'wrong-password',
        ]));

        $response->assertStatus(401)
            ->assertJson([
                'message' => 'Email atau password salah.',
                'code' => 'INVALID_CREDENTIALS',
            ])
            ->assertJsonMissingPath('data');
    }

    public function test_login_fails_with_inactive_account(): void
    {
        $this->makeUser(['is_active' => false]);

        $response = $this->postJson('/api/v1/auth/login', $this->credentials());

        $response->assertStatus(403)
            ->assertJson([
                'code' => 'ACCOUNT_INACTIVE',
            ]);
    }

    public function test_login_validates_input(): void
    {
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => 'not-an-email',
            'password' => '',
        ]);

        $response->assertStatus(422)
            ->assertJson([
                'message' => 'Data tidak valid.',
                'code' => 'VALIDATION_ERROR',
            ])
            ->assertJsonStructure([
                'errors' => ['email', 'password'],
            ]);
    }

    public function test_me_requires_authentication(): void
    {
        $response = $this->getJson('/api/v1/me');

        $response->assertStatus(401)
            ->assertJson([
                'message' => 'Unauthenticated.',
                'code' => 'UNAUTHENTICATED',
            ]);
    }

    public function test_me_returns_authenticated_user(): void
    {
        $user = $this->makeUser(['role' => UserRole::HR]);
        $token = $user->createToken('aaj-mobile')->plainTextToken;

        $response = $this->getJson('/api/v1/me', [
            'Authorization' => "Bearer {$token}",
        ]);

        $response->assertOk()
            ->assertJsonPath('data.id', $user->id)
            ->assertJsonPath('data.email', $user->email)
            ->assertJsonPath('data.role', UserRole::HR->value);
    }

    public function test_logout_revokes_current_token(): void
    {
        $user = $this->makeUser();
        $token = $user->createToken('aaj-mobile')->plainTextToken;

        $response = $this->postJson('/api/v1/auth/logout', [], [
            'Authorization' => "Bearer {$token}",
        ]);

        $response->assertOk();
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_me_rejects_a_revoked_token(): void
    {
        $user = $this->makeUser();
        $token = $user->createToken('aaj-mobile')->plainTextToken;

        $user->tokens()->delete();

        $response = $this->getJson('/api/v1/me', [
            'Authorization' => "Bearer {$token}",
        ]);

        $response->assertStatus(401)
            ->assertJson([
                'code' => 'UNAUTHENTICATED',
            ]);
    }
}
