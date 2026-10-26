<?php

namespace Tests\Feature\Api\V1;

use App\Models\AttendanceEvent;
use App\Models\Device;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class AttendanceServerTimeTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    public function test_client_past_event_time_is_ignored_for_status_and_event_at(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001')->assertOk();
        $this->travelToAttendanceTime('12:00');

        $response = $this->postEventVia($user, 'device-0001', [], [
            'event_at' => $this->eventAt('01:00'),
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.status', 'LATE')
            ->assertJsonPath('data.event_at', '2026-10-06T04:00:00.000000Z')
            ->assertJsonPath('data.server_received_at', '2026-10-06T04:00:00.000000Z');

        $event = AttendanceEvent::firstOrFail();
        $this->assertSame('2026-10-06 04:00:00', $event->event_at->utc()->format('Y-m-d H:i:s'));
    }

    public function test_client_future_event_time_is_ignored_for_status_and_event_at(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001')->assertOk();
        $this->travelToAttendanceTime('08:00');

        $response = $this->postEventVia($user, 'device-0001', [], [
            'event_at' => $this->eventAt('23:00'),
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.status', 'ON_TIME')
            ->assertJsonPath('data.event_at', '2026-10-06T00:00:00.000000Z');
    }

    public function test_device_clock_difference_does_not_change_server_status(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001')->assertOk();
        $this->travelToAttendanceTime('08:35');

        $response = $this->postEventVia($user, 'device-0001', [], [
            'event_at' => $this->eventAt('18:35'),
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.status', 'ON_TIME')
            ->assertJsonPath('data.event_at', '2026-10-06T00:35:00.000000Z');
    }

    public function test_event_at_is_optional_and_server_time_is_used(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001')->assertOk();
        $this->travelToAttendanceTime('08:30');

        $payload = array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => 'device-0001',
            'event_type' => 'CHECK_IN',
            'photo' => $this->photoUpload(),
        ], $this->gpsInside());

        $response = $this->post('/api/v1/attendance/events', $payload, $this->tokenHeader($user));

        $response->assertCreated()
            ->assertJsonPath('data.status', 'ON_TIME')
            ->assertJsonPath('data.event_at', '2026-10-06T00:30:00.000000Z');
    }

    public function test_sequence_uses_server_received_time_not_client_event_time(): void
    {
        Storage::fake('local');

        [$user, $employee] = $this->makeEmployeeUser();
        $this->travelToAttendanceTime('08:00');
        $this->registerDeviceVia($user, 'device-0001')->assertOk();
        $this->postEventVia($user, 'device-0001')->assertCreated();

        $device = Device::firstOrFail();

        AttendanceEvent::query()->create([
            'client_event_id' => (string) Str::uuid(),
            'employee_id' => $employee->id,
            'device_id' => $device->id,
            'event_type' => 'CHECK_OUT',
            'event_at' => Carbon::parse('2020-01-01 00:00:00', 'UTC'),
            'status' => 'NORMAL',
            'sync_source' => 'mobile',
            'server_received_at' => Carbon::parse('2026-10-06 09:00:00', 'Asia/Makassar'),
        ]);

        $this->travelToAttendanceTime('10:00');

        $response = $this->postEventVia($user, 'device-0001', [
            'event_type' => 'CHECK_IN',
            'event_at' => $this->eventAt('20:00'),
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.status', 'LATE');

        $this->assertDatabaseCount('attendance_events', 3);
    }

    public function test_captured_at_is_stored_as_photo_metadata_without_affecting_attendance_time(): void
    {
        Storage::fake('local');

        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001')->assertOk();
        $this->travelToAttendanceTime('08:00');

        $response = $this->postEventVia($user, 'device-0001', [
            'captured_at' => '2020-01-01T00:00:00Z',
            'event_at' => $this->eventAt('23:00'),
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.status', 'ON_TIME')
            ->assertJsonPath('data.event_at', '2026-10-06T00:00:00.000000Z')
            ->assertJsonPath('data.photo.captured_at', '2020-01-01T00:00:00.000000Z');
    }

    public function test_replay_uses_existing_event_even_after_server_time_changes(): void
    {
        Storage::fake('local');

        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001')->assertOk();
        $this->travelToAttendanceTime('08:00');

        $clientEventId = (string) Str::uuid();

        $first = $this->postEventVia($user, 'device-0001', [
            'client_event_id' => $clientEventId,
            'event_at' => $this->eventAt('08:00'),
        ]);
        $first->assertCreated();

        $this->travelToAttendanceTime('12:00');

        $second = $this->postEventVia($user, 'device-0001', [
            'client_event_id' => $clientEventId,
            'event_at' => $this->eventAt('12:00'),
        ]);

        $second->assertOk()
            ->assertJsonPath('data.id', $first->json('data.id'))
            ->assertJsonPath('data.event_at', '2026-10-06T00:00:00.000000Z');

        $this->assertDatabaseCount('attendance_events', 1);
        $this->assertDatabaseCount('attendance_photos', 1);
        $this->assertCount(1, Storage::disk('local')->allFiles('attendance'));
    }
}
