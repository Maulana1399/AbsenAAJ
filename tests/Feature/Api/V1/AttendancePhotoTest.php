<?php

namespace Tests\Feature\Api\V1;

use App\Models\AttendanceEvent;
use App\Models\AttendancePhoto;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class AttendancePhotoTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    private function postEventPayload(array $overrides = []): array
    {
        return array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => 'device-0001',
            'event_type' => 'CHECK_IN',
            'event_at' => $this->eventAt('08:00'),
            'photo' => $this->photoUpload(),
        ], $this->gpsInside(), $overrides);
    }

    public function test_photo_is_required(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $payload = $this->postEventPayload(['photo' => '']);
        unset($payload['photo']);

        $response = $this->post('/api/v1/attendance/events', $payload, $this->tokenHeader($user));

        $response->assertStatus(422)
            ->assertJson(['code' => 'VALIDATION_ERROR'])
            ->assertJsonValidationErrors('photo');

        $this->assertDatabaseCount('attendance_events', 0);
    }

    public function test_invalid_mime_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $payload = $this->postEventPayload([
            'photo' => UploadedFile::fake()->create('malware.exe', 5, 'application/x-msdownload'),
        ]);

        $response = $this->post('/api/v1/attendance/events', $payload, $this->tokenHeader($user));

        $response->assertStatus(422)
            ->assertJsonValidationErrors('photo');
    }

    public function test_php_file_disguised_as_image_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $payload = $this->postEventPayload([
            'photo' => UploadedFile::fake()->create('selfie.php', 2, 'image/jpeg'),
        ]);

        $response = $this->post('/api/v1/attendance/events', $payload, $this->tokenHeader($user));

        $response->assertStatus(422)
            ->assertJsonValidationErrors('photo');
    }

    public function test_oversized_photo_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $maxKb = (int) config('attendance.photo.max_kilobytes');

        $payload = $this->postEventPayload([
            'photo' => UploadedFile::fake()->create('big.jpg', $maxKb + 500, 'image/jpeg'),
        ]);

        $response = $this->post('/api/v1/attendance/events', $payload, $this->tokenHeader($user));

        $response->assertStatus(422)
            ->assertJsonValidationErrors('photo');
    }

    public function test_valid_photo_is_stored_privately_with_metadata(): void
    {
        Storage::fake('local');

        [$user, $employee] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $filename = 'selfie-'.Str::random(4).'.jpg';
        $photo = $this->photoUpload($filename);

        $payload = $this->postEventPayload([
            'photo' => $photo,
            'captured_at' => '2026-10-06T08:00:00+08:00',
        ]);

        $response = $this->post('/api/v1/attendance/events', $payload, $this->tokenHeader($user));

        $response->assertCreated()
            ->assertJsonStructure([
                'data' => [
                    'latitude', 'longitude', 'accuracy_meters', 'distance_meters', 'location_valid',
                    'photo' => ['id', 'mime_type', 'file_size', 'sha256', 'captured_at'],
                ],
            ]);

        $this->assertDatabaseCount('attendance_photos', 1);

        $photoRecord = AttendancePhoto::firstOrFail();
        $this->assertSame($payload['client_event_id'], $response->json('data.client_event_id'));
        $this->assertStringStartsWith('attendance/', $photoRecord->storage_path);
        $this->assertTrue(Storage::disk('local')->exists($photoRecord->storage_path));
        $this->assertSame($filename, $photoRecord->original_filename);
        $this->assertSame($photo->getMimeType(), $photoRecord->mime_type);
        $this->assertSame($photo->getSize(), (int) $photoRecord->file_size);
        $this->assertSame(64, strlen($photoRecord->sha256));
        $this->assertNotNull($photoRecord->captured_at);

        $this->assertSame($response->json('data.photo.id'), $photoRecord->id);
        $this->assertSame($response->json('data.photo.sha256'), $photoRecord->sha256);
    }

    public function test_sha256_is_computed_by_server_not_client(): void
    {
        Storage::fake('local');

        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $payload = $this->postEventPayload([
            'client_hash' => str_repeat('f', 64),
        ]);

        $response = $this->post('/api/v1/attendance/events', $payload, $this->tokenHeader($user));

        $response->assertCreated();

        $record = AttendancePhoto::firstOrFail();
        $stored = hash_file('sha256', Storage::disk('local')->path($record->storage_path));

        $this->assertNotSame(str_repeat('f', 64), $record->sha256);
        $this->assertSame($stored, $record->sha256);
        $this->assertSame($stored, $response->json('data.photo.sha256'));
    }

    public function test_photo_response_never_exposes_path_or_public_url(): void
    {
        Storage::fake('local');

        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->post('/api/v1/attendance/events', $this->postEventPayload(), $this->tokenHeader($user));

        $response->assertCreated();

        $body = $response->getContent();
        $this->assertStringNotContainsString('storage_path', $body);
        $this->assertStringNotContainsString('/storage/', $body);
        $this->assertStringNotContainsString('/var/www', $body);
        $this->assertStringNotContainsString('/tmp', $body);

        $record = AttendancePhoto::firstOrFail();
        $this->assertFalse(Storage::disk('public')->exists($record->storage_path));

        $this->get('/storage/'.ltrim($record->storage_path, '/'))
            ->assertStatus(404);
    }

    public function test_every_event_photo_is_unique_and_linked_to_one_event(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $this->post('/api/v1/attendance/events', $this->postEventPayload(), $this->tokenHeader($user))->assertCreated();

        $this->assertSame(1, AttendancePhoto::count());

        $photo = AttendancePhoto::firstOrFail();
        $this->assertSame(AttendanceEvent::value('id'), $photo->attendance_event_id);
    }
}
