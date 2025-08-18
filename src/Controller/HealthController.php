<?php

namespace App\Controller;

use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Annotation\Route;

/** @psalm-suppress UnusedClass */
final class HealthController
{
    #[Route('/health', name: 'app_health', methods: ['GET'])]
    public function __invoke(EntityManagerInterface $em): JsonResponse
    {
        $dbOk = false;
        try {
            $em->getConnection()->executeQuery('SELECT 1');
            $dbOk = true;
        } catch (\Throwable $e) {
            $dbOk = false;
        }

        return new JsonResponse([
            'status' => 'ok',
            'env' => $_ENV['APP_ENV'] ?? 'unknown',
            'db' => $dbOk,
        ]);
    }
}
