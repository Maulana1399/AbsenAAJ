<?php

use App\Exceptions\ApiException;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Routing\Exceptions\InvalidSignatureException;
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\Http\Middleware\EnsureFrontendRequestsAreStateful;
use Symfony\Component\HttpFoundation\Exception\RequestExceptionInterface;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->api(prepend: [
            EnsureFrontendRequestsAreStateful::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );

        $exceptions->render(function (Throwable $e, Request $request) {
            if (! $request->is('api/*') && ! $request->expectsJson()) {
                return null;
            }

            if ($e instanceof ApiException) {
                return $e->render();
            }

            if ($e instanceof AuthenticationException) {
                return response()->json([
                    'message' => 'Unauthenticated.',
                    'code' => 'UNAUTHENTICATED',
                ], 401);
            }

            if ($e instanceof ValidationException) {
                return response()->json([
                    'message' => 'Data tidak valid.',
                    'code' => 'VALIDATION_ERROR',
                    'errors' => $e->errors(),
                ], 422);
            }

            if ($e instanceof AuthorizationException) {
                return response()->json([
                    'message' => $e->getMessage() !== '' ? $e->getMessage() : 'Forbidden.',
                    'code' => 'FORBIDDEN',
                ], 403);
            }

            if ($e instanceof NotFoundHttpException || $e instanceof InvalidSignatureException) {
                return response()->json([
                    'message' => 'Resource tidak ditemukan.',
                    'code' => 'NOT_FOUND',
                ], 404);
            }

            $status = $e instanceof HttpExceptionInterface
                ? $e->getStatusCode()
                : ($e instanceof RequestExceptionInterface ? 400 : 500);

            $message = $status >= 500 && ! config('app.debug')
                ? 'Terjadi kesalahan.'
                : $e->getMessage();

            return response()->json([
                'message' => $message,
                'code' => $status >= 500 ? 'INTERNAL_ERROR' : 'ERROR',
            ], $status);
        });
    })->create();
