<?php

namespace Tests\Feature\Api\V1;

use App\Models\AttendanceEvent;
use App\Models\AttendancePhoto;
use Illuminate\Database\Events\QueryExecuted;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class AttendanceTransactionTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    public function test_failed_photo_upload_leaves_no_event_no_photo_record_no_file(): void
    {
        Storage::fake('local');

        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $failed = false;
        Event::listen(QueryExecuted::class, function (QueryExecuted $query) use (&$failed): void {
            if (! $failed
                && str_contains($query->sql, 'insert into')
                && str_contains($query->sql, 'attendance_events')
            ) {
                $failed = true;

                throw new \RuntimeException('simulated persistence failure');
            }
        });

        $response = $this->post('/api/v1/attendance/events', array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => 'device-0001',
            'event_type' => 'CHECK_IN',
            'event_at' => $this->eventAt('08:00'),
            'photo' => $this->photoUpload(),
        ], $this->gpsInside()), $this->tokenHeader($user));

        $response->assertStatus(500);

        $this->assertTrue($failed, 'failure point was not reached');
        $this->assertDatabaseCount('attendance_events', 0);
        $this->assertDatabaseCount('attendance_photos', 0);
        $this->assertEmpty(Storage::disk('local')->allFiles('attendance'));
    }

    public function test_successful_event_always_has_exactly_one_photo_record(): void
    {
        Storage::fake('local');

        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $this->post('/api/v1/attendance/events', array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => 'device-0001',
            'event_type' => 'CHECK_IN',
            'event_at' => $this->eventAt('08:00'),
            'photo' => $this->photoUpload(),
        ], $this->gpsInside()), $this->tokenHeader($user))->assertCreated();

        $event = AttendanceEvent::firstOrFail();

        $this->assertTrue($event->photo()->exists());
        $this->assertSame(1, AttendancePhoto::count());
        $this->assertCount(1, Storage::disk('local')->allFiles('attendance'));
    }

    public function test_retry_of_same_client_event_id_does_not_duplicate_photo(): void
    {
        Storage::fake('local');

        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $clientEventId = (string) Str::uuid();

        $payload = array_merge([
            'client_event_id' => $clientEventId,
            'device_uuid' => 'device-0001',
            'event_type' => 'CHECK_IN',
            'event_at' => $this->eventAt('08:00'),
            'photo' => $this->photoUpload(),
        ], $this->gpsInside());

        $this->post('/api/v1/attendance/events', $payload, $this->tokenHeader($user))->assertCreated();
        $this->post('/api/v1/attendance/events', $payload, $this->tokenHeader($user))->assertOk();

        $this->assertDatabaseCount('attendance_events', 1);
        $this->assertDatabaseCount('attendance_photos', 1);
        $this->assertCount(1, Storage::disk('local')->allFiles('attendance'));
    }
}
