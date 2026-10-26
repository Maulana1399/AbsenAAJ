<?php

namespace Tests\Feature\Api\V1;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class TokenLifecycleTest extends TestCase
{
    use RefreshDatabase;

    private function makeUser(array $attributes = []): User
    {
        return User::factory()->create(array_merge([
            'email' => 'employee@example.com',
            'password' => 'secret-password',
        ], $attributes));
    }

    private function credentials(): array
    {
        return [
            'email' => 'employee@example.com',
            'password' => 'secret-password',
        ];
    }

    private function forgetGuards(): void
    {
        $this->app->make('auth')->forgetGuards();
    }

    public function test_token_expires_after_configured_minutes(): void
    {
        $user = $this->makeUser();
        $token = $user->createToken('aaj-mobile')->plainTextToken;
        $expiration = (int) config('sanctum.expiration');

        $this->assertGreaterThan(0, $expiration);

        $this->getJson('/api/v1/me', [
            'Authorization' => "Bearer {$token}",
        ])->assertOk();

        $this->forgetGuards();
        $this->travel($expiration + 1)->minutes();

        $response = $this->getJson('/api/v1/me', [
            'Authorization' => "Bearer {$token}",
        ]);

        $response->assertUnauthorized()
            ->assertJson([
                'code' => 'UNAUTHENTICATED',
            ]);
    }

    public function test_deactivating_user_revokes_all_tokens(): void
    {
        $user = $this->makeUser();
        $user->createToken('first-device');
        $user->createToken('second-device');

        $this->assertDatabaseCount('personal_access_tokens', 2);

        $user->update(['is_active' => false]);

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_revoked_token_cannot_access_authenticated_endpoints(): void
    {
        $user = $this->makeUser();
        $token = $user->createToken('aaj-mobile')->plainTextToken;

        $user->update(['is_active' => false]);

        $requests = [
            ['GET', '/api/v1/me', []],
            ['GET', '/api/v1/attendance', []],
            ['POST', '/api/v1/devices/register', []],
        ];

        foreach ($requests as [$method, $uri, $payload]) {
            $this->forgetGuards();

            $response = $this->json($method, $uri, $payload, [
                'Authorization' => "Bearer {$token}",
            ]);

            $response->assertUnauthorized()
                ->assertJson([
                    'code' => 'UNAUTHENTICATED',
                ]);
        }
    }

    public function test_stale_token_for_deactivated_user_is_rejected_by_middleware(): void
    {
        $user = $this->makeUser();
        $token = $user->createToken('aaj-mobile')->plainTextToken;

        DB::table('users')->where('id', $user->id)->update(['is_active' => false]);

        $this->assertDatabaseCount('personal_access_tokens', 1);

        $requests = [
            ['GET', '/api/v1/me', []],
            ['GET', '/api/v1/attendance', []],
            ['POST', '/api/v1/devices/register', []],
        ];

        foreach ($requests as [$method, $uri, $payload]) {
            $this->forgetGuards();

            $response = $this->json($method, $uri, $payload, [
                'Authorization' => "Bearer {$token}",
            ]);

            $response->assertForbidden()
                ->assertJson([
                    'message' => 'Akun anda tidak aktif. Hubungi HR.',
                    'code' => 'ACCOUNT_INACTIVE',
                ]);
        }
    }

    public function test_reactivated_account_requires_a_new_token(): void
    {
        $user = $this->makeUser();
        $oldToken = $user->createToken('aaj-mobile')->plainTextToken;

        $user->update(['is_active' => false]);
        $user->update(['is_active' => true]);

        $this->getJson('/api/v1/me', [
            'Authorization' => "Bearer {$oldToken}",
        ])->assertUnauthorized();

        $login = $this->postJson('/api/v1/auth/login', $this->credentials());

        $login->assertOk();
        $newToken = $login->json('data.token');
        $this->assertNotSame($oldToken, $newToken);

        $this->forgetGuards();

        $this->getJson('/api/v1/me', [
            'Authorization' => "Bearer {$newToken}",
        ])->assertOk();
    }

    public function test_logout_revokes_only_the_current_token(): void
    {
        $user = $this->makeUser();
        $currentToken = $user->createToken('current-device')->plainTextToken;
        $otherToken = $user->createToken('other-device')->plainTextToken;

        $this->postJson('/api/v1/auth/logout', [], [
            'Authorization' => "Bearer {$currentToken}",
        ])->assertOk();

        $this->assertDatabaseCount('personal_access_tokens', 1);

        $this->forgetGuards();

        $this->getJson('/api/v1/me', [
            'Authorization' => "Bearer {$otherToken}",
        ])->assertOk();
    }
}
