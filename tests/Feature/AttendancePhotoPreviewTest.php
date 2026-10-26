<?php

namespace Tests\Feature;

use App\Filament\Resources\AttendanceEvents\Pages\ListAttendanceEvents;
use App\Models\AttendanceEvent;
use App\Models\AttendancePhoto;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Livewire\Livewire;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class AttendancePhotoPreviewTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    private function makeEventWithPhoto(bool $storeFile = true): AttendanceEvent
    {
        [, $employee] = $this->makeEmployeeUser();

        $event = AttendanceEvent::factory()->create([
            'employee_id' => $employee->id,
        ]);

        $path = 'attendance/test/selfie.jpg';
        $photo = UploadedFile::fake()->image('selfie.jpg', 10, 10);

        if ($storeFile) {
            Storage::disk('local')->put($path, file_get_contents($photo->getRealPath()));
        }

        AttendancePhoto::factory()->create([
            'attendance_event_id' => $event->id,
            'storage_path' => $path,
            'original_filename' => 'selfie.jpg',
            'mime_type' => 'image/jpeg',
            'file_size' => Storage::disk('local')->exists($path) ? Storage::disk('local')->size($path) : 1000,
            'sha256' => str_repeat('a', 64),
        ]);

        return $event;
    }

    public function test_admin_can_view_attendance_photo(): void
    {
        Storage::fake('local');

        $admin = User::factory()->admin()->create();
        $event = $this->makeEventWithPhoto();

        $response = $this->actingAs($admin)->get(route('admin.attendance-events.photo', $event));

        $response->assertOk()
            ->assertHeader('content-type', 'image/jpeg')
            ->assertHeader('x-content-type-options', 'nosniff');

        $this->assertStringContainsString('inline', $response->headers->get('content-disposition'));
    }

    public function test_hr_can_view_attendance_photo(): void
    {
        Storage::fake('local');

        $hr = User::factory()->hr()->create();
        $event = $this->makeEventWithPhoto();

        $this->actingAs($hr)
            ->get(route('admin.attendance-events.photo', $event))
            ->assertOk();
    }

    public function test_guest_is_redirected_to_admin_login(): void
    {
        Storage::fake('local');

        $event = $this->makeEventWithPhoto();

        $this->get(route('admin.attendance-events.photo', $event))
            ->assertRedirect(route('filament.admin.auth.login'));
    }

    public function test_employee_cannot_view_attendance_photo(): void
    {
        Storage::fake('local');

        [$employeeUser] = $this->makeEmployeeUser();
        $event = $this->makeEventWithPhoto();

        $this->actingAs($employeeUser)
            ->get(route('admin.attendance-events.photo', $event))
            ->assertForbidden();
    }

    public function test_missing_photo_file_returns_not_found(): void
    {
        Storage::fake('local');

        $admin = User::factory()->admin()->create();
        $event = $this->makeEventWithPhoto(storeFile: false);

        $this->actingAs($admin)
            ->get(route('admin.attendance-events.photo', $event))
            ->assertNotFound();
    }

    public function test_photo_preview_shows_message_when_photo_file_is_missing(): void
    {
        Storage::fake('local');

        $event = $this->makeEventWithPhoto(storeFile: false);

        $html = view('filament.attendance-events.photo-preview', [
            'photo' => $event->photo,
            'url' => null,
        ])->render();

        $this->assertStringContainsString('File foto selfie tidak ditemukan pada penyimpanan.', $html);
    }

    public function test_event_without_photo_returns_not_found(): void
    {
        Storage::fake('local');

        $admin = User::factory()->admin()->create();
        [, $employee] = $this->makeEmployeeUser();
        $event = AttendanceEvent::factory()->create(['employee_id' => $employee->id]);

        $this->actingAs($admin)
            ->get(route('admin.attendance-events.photo', $event))
            ->assertNotFound();
    }

    public function test_table_has_view_photo_action(): void
    {
        $admin = User::factory()->admin()->create();

        Livewire::actingAs($admin)
            ->test(ListAttendanceEvents::class)
            ->assertSuccessful()
            ->assertTableActionExists('viewPhoto');
    }
}
