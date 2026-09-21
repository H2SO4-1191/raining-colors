import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:math';
import 'dart:async';

void main() {
  runApp(const GameApp());
}

class GameApp extends StatelessWidget {
  const GameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raining Colors',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const GameHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Target {
  final Color color;
  final Offset position;
  final double size;
  final int id;

  Target({
    required this.color,
    required this.position,
    required this.size,
    required this.id,
  });

  Target copyWith({Color? color, Offset? position, double? size}) {
    return Target(
      color: color ?? this.color,
      position: position ?? this.position,
      size: size ?? this.size,
      id: id,
    );
  }
}

class Particle {
  final Offset position;
  final Offset velocity;
  final Color color;
  final double life;

  Particle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.life,
  });
}

class GameHomePage extends StatefulWidget {
  const GameHomePage({super.key});

  @override
  State<GameHomePage> createState() => _GameHomePageState();
}

class _GameHomePageState extends State<GameHomePage>
    with WidgetsBindingObserver {
  // Game state
  bool isPlaying = false;
  bool isPaused = false;
  int score = 0;
  int highScore = 0;
  int lives = 3;
  double gameSpeed = 1.0;
  int level = 1;
  Color? targetColor;
  List<Target> targets = [];
  Timer? gameTimer;
  Timer? spawnTimer;
  Random random = Random();
  int targetIdCounter = 0;

  // Visual effects state
  Color? _flashColor;
  Offset _shakeOffset = Offset.zero;
  Offset? _pulsePosition;
  double _pulseRadius = 0.0;
  List<Particle> _particles = [];
  Timer? _effectTimer;

  // Settings
  String playerName = '';
  String difficulty = 'Medium';
  double spawnRate = 1.5;
  double targetSpeed = 2.0;
  bool showParticles = true;
  bool showTrails = false;
  bool soundEnabled = true;
  bool vibrationEnabled = true;
  int targetCount = 3;

  final TextEditingController _nameController = TextEditingController();
  final AudioPlayer _backgroundMusicPlayer =
      AudioPlayer(); // For background music (never stops)
  final List<Color> gameColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start background music when app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBackgroundMusic();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Pause/resume background music based on app state
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // App is in background or minimized - pause music
      _backgroundMusicPlayer.pause();
    } else if (state == AppLifecycleState.resumed) {
      // App is back in foreground - resume music if sound is enabled
      if (soundEnabled) {
        _backgroundMusicPlayer.resume();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _backgroundMusicPlayer.dispose();
    gameTimer?.cancel();
    spawnTimer?.cancel();
    _effectTimer?.cancel();
    super.dispose();
  }

  void startGame() {
    if (isPlaying) return;

    // Cancel any existing timers
    gameTimer?.cancel();
    spawnTimer?.cancel();

    if (vibrationEnabled) {
      HapticFeedback.heavyImpact();
    }

    setState(() {
      isPlaying = true;
      isPaused = false;
      score = 0;
      lives = 3;
      gameSpeed = 1.0;
      level = 1;
      targets.clear();
      targetIdCounter = 0;
      _updateDifficulty();
      _setNewTargetColor();
    });

    // Spawn targets periodically
    spawnTimer = Timer.periodic(
      Duration(milliseconds: (spawnRate * 1000).toInt()),
      (_) {
        if (isPlaying && !isPaused && mounted) {
          _spawnTarget();
        }
      },
    );

    // Game loop
    gameTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!isPaused && isPlaying && mounted) {
        _updateGame();
      }
    });
  }

  void _updateDifficulty() {
    switch (difficulty) {
      case 'Easy':
        spawnRate = 2.0;
        targetSpeed = 1.5;
        targetCount = 2;
        break;
      case 'Medium':
        spawnRate = 1.5;
        targetSpeed = 2.0;
        targetCount = 3;
        break;
      case 'Hard':
        spawnRate = 1.0;
        targetSpeed = 2.5;
        targetCount = 4;
        break;
      case 'Extreme':
        spawnRate = 0.7;
        targetSpeed = 3.0;
        targetCount = 5;
        break;
    }
  }

  Set<Color> _getColorsBelowY(double yPosition) {
    // Get all colors that have targets below (higher Y) than the given position
    final colorsBelow = <Color>{};
    for (final target in targets) {
      if (target.position.dy > yPosition) {
        colorsBelow.add(target.color);
      }
    }
    return colorsBelow;
  }

  void _setNewTargetColor([double? hitTargetY]) {
    setState(() {
      Color? newColor;
      int attempts = 0;
      const maxAttempts = 50;

      // If we have a hit target Y position, get all colors that are below it
      Set<Color>? colorsToAvoid;
      if (hitTargetY != null) {
        colorsToAvoid = _getColorsBelowY(hitTargetY);

        // Get available colors (colors NOT in the avoid list)
        final availableColors = gameColors
            .where((color) => !colorsToAvoid!.contains(color))
            .toList();

        if (availableColors.isNotEmpty) {
          // Pick randomly from available colors (colors NOT below the hit target)
          newColor = availableColors[random.nextInt(availableColors.length)];
        }
        // If all colors are below, we'll fall through to the fallback logic
      }

      // If no color found yet, try to find one that's not near the bottom
      if (newColor == null) {
        attempts = 0;
        while (newColor == null && attempts < maxAttempts) {
          final candidateColor = gameColors[random.nextInt(gameColors.length)];
          if (!_hasColorNearBottom(candidateColor)) {
            newColor = candidateColor;
            break;
          }
          attempts++;
        }
      }

      // If all colors are problematic, pick the one with furthest target from bottom
      if (newColor == null) {
        final screenHeight = MediaQuery.of(context).size.height;
        double maxDistance = -1;
        Color? safestColor;

        for (final color in gameColors) {
          double minDistance = double.infinity;
          for (final target in targets) {
            if (target.color == color) {
              final distance = screenHeight - target.position.dy;
              if (distance < minDistance) {
                minDistance = distance;
              }
            }
          }
          if (minDistance > maxDistance) {
            maxDistance = minDistance;
            safestColor = color;
          }
        }
        newColor = safestColor ?? gameColors[0];
      }

      targetColor = newColor;
    });
  }

  bool _checkOverlap(
    Offset position,
    double size,
    List<Target> existingTargets,
  ) {
    for (final target in existingTargets) {
      final distance = sqrt(
        pow(position.dx - target.position.dx, 2) +
            pow(position.dy - target.position.dy, 2),
      );
      final minDistance = (size / 2) + (target.size / 2) + 10; // 10px padding
      if (distance < minDistance) {
        return true; // Overlaps
      }
    }
    return false; // No overlap
  }

  bool _hasColorNearBottom(Color color) {
    if (!mounted) return false;
    final screenHeight = MediaQuery.of(context).size.height;
    const dangerZone = 200.0; // Pixels from bottom where targets are dangerous

    for (final target in targets) {
      if (target.color == color &&
          target.position.dy > screenHeight - dangerZone) {
        return true;
      }
    }
    return false;
  }

  void _spawnTarget() {
    if (!isPlaying || isPaused || !mounted) return;

    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;

    setState(() {
      final newTargets = <Target>[];

      for (int i = 0; i < targetCount; i++) {
        final color = gameColors[random.nextInt(gameColors.length)];
        final size = 40.0 + random.nextDouble() * 30.0;

        // Try to find a non-overlapping position
        Offset? position;
        int attempts = 0;
        const maxAttempts = 50;

        while (position == null && attempts < maxAttempts) {
          final x = size + random.nextDouble() * (screenWidth - size * 2);
          final y = -size - random.nextDouble() * 100;
          final candidatePosition = Offset(x, y);

          // Check overlap with existing targets and newly added targets
          if (!_checkOverlap(candidatePosition, size, targets) &&
              !_checkOverlap(candidatePosition, size, newTargets)) {
            position = candidatePosition;
          }
          attempts++;
        }

        // If we couldn't find a non-overlapping position, use the last attempt
        if (position == null) {
          final x = size + random.nextDouble() * (screenWidth - size * 2);
          final y = -size - random.nextDouble() * 100;
          position = Offset(x, y);
        }

        newTargets.add(
          Target(
            color: color,
            position: position,
            size: size,
            id: targetIdCounter++,
          ),
        );
      }

      targets.addAll(newTargets);
    });
  }

  void _updateGame() {
    if (!mounted) return;

    final screenHeight = MediaQuery.of(context).size.height;

    setState(() {
      // Move targets down
      targets = targets.map((target) {
        final newY = target.position.dy + targetSpeed * gameSpeed;
        return target.copyWith(position: Offset(target.position.dx, newY));
      }).toList();

      // Remove targets that went off screen
      targets.removeWhere((target) => target.position.dy > screenHeight + 100);

      // Increase difficulty over time
      final newLevel = (score ~/ 50) + 1;
      if (newLevel > level) {
        level = newLevel;
        gameSpeed = min(1.0 + (level - 1) * 0.1, 3.0);
      }

      // Check if targets reached bottom (lose life)
      targets.removeWhere((target) {
        if (target.position.dy > screenHeight - 100) {
          if (target.color == targetColor) {
            // Correct target missed
            lives--;
            final missPosition = Offset(target.position.dx, target.position.dy);

            // Trigger INTENSE vibration and visual effects for missed target
            if (vibrationEnabled) {
              HapticFeedback.heavyImpact();
              Future.delayed(const Duration(milliseconds: 30), () {
                HapticFeedback.heavyImpact();
              });
              Future.delayed(const Duration(milliseconds: 60), () {
                HapticFeedback.heavyImpact();
              });
              Future.delayed(const Duration(milliseconds: 90), () {
                HapticFeedback.heavyImpact();
              });
              Future.delayed(const Duration(milliseconds: 120), () {
                HapticFeedback.heavyImpact();
              });
              Future.delayed(const Duration(milliseconds: 150), () {
                HapticFeedback.heavyImpact();
              });
              Future.delayed(const Duration(milliseconds: 180), () {
                HapticFeedback.heavyImpact();
              });
            }
            _triggerVisualEffect(false, missPosition);

            if (lives <= 0) {
              _gameOver();
            }
          }
          return true;
        }
        return false;
      });
    });
  }

  Future<void> _startBackgroundMusic() async {
    if (!soundEnabled) return;

    await _backgroundMusicPlayer.stop();
    await _backgroundMusicPlayer.setReleaseMode(ReleaseMode.loop);
    await _backgroundMusicPlayer.setVolume(0.3);

    await _backgroundMusicPlayer.play(
      AssetSource('sounds/background_music.mp3'),
    );
  }

  void _triggerVibration(bool isCorrect) {
    if (!vibrationEnabled) return;

    if (isCorrect) {
      // CRAZY vibration for correct hit - INSANE rapid fire pattern
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 20), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 40), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 60), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 80), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 120), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 140), () {
        HapticFeedback.heavyImpact();
      });
    } else {
      // INTENSE vibration for wrong hit - LONGER, STRONGER pattern
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 30), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 60), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 90), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 120), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 150), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 180), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 210), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 240), () {
        HapticFeedback.heavyImpact();
      });
    }
  }

  void _triggerVisualEffect(bool isCorrect, Offset position) {
    setState(() {
      // INTENSE screen flash - brighter and more visible
      _flashColor = isCorrect ? Colors.green : Colors.red;

      // CRAZY screen shake - much stronger
      _shakeOffset = Offset(
        (random.nextDouble() - 0.5) * 40,
        (random.nextDouble() - 0.5) * 40,
      );

      // Pulse effect
      _pulsePosition = position;
      _pulseRadius = 0.0;

      // MASSIVE particle explosion - way more particles
      _particles.clear();
      final particleCount = isCorrect
          ? 40
          : 50; // More particles for heart loss
      for (int i = 0; i < particleCount; i++) {
        final angle = (i * 2 * pi) / particleCount;
        final speed = 5.0 + random.nextDouble() * 8.0; // Faster particles
        _particles.add(
          Particle(
            position: position,
            velocity: Offset(cos(angle) * speed, sin(angle) * speed),
            color: isCorrect
                ? Colors.greenAccent
                : Colors.redAccent, // Brighter colors
            life: 1.0,
          ),
        );
      }
    });

    // Animate effects
    _effectTimer?.cancel();
    int frame = 0;
    _effectTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      frame++;

      setState(() {
        // Fade flash - slower fade for more visibility
        if (_flashColor != null) {
          final alpha = 1.0 - (frame * 0.03); // Slower fade
          if (alpha <= 0) {
            _flashColor = null;
          }
        }

        // Reduce shake - slower reduction for more dramatic effect
        _shakeOffset = Offset(
          _shakeOffset.dx * 0.7, // Slower reduction
          _shakeOffset.dy * 0.7,
        );
        if (_shakeOffset.distance < 0.1) {
          _shakeOffset = Offset.zero;
        }

        // Expand pulse - faster and bigger
        if (_pulsePosition != null) {
          _pulseRadius += 12.0; // Faster expansion
          if (_pulseRadius > 400) {
            // Bigger radius
            _pulsePosition = null;
            _pulseRadius = 0.0;
          }
        }

        // Update particles - slower fade for more visibility
        _particles = _particles
            .map((particle) {
              return Particle(
                position: Offset(
                  particle.position.dx + particle.velocity.dx,
                  particle.position.dy + particle.velocity.dy,
                ),
                velocity: Offset(
                  particle.velocity.dx * 0.92, // Slower deceleration
                  particle.velocity.dy * 0.92,
                ),
                color: particle.color,
                life: particle.life - 0.015, // Slower fade
              );
            })
            .where((particle) => particle.life > 0)
            .toList();
      });

      if (frame > 60 &&
          _particles.isEmpty &&
          _flashColor == null &&
          _pulsePosition == null) {
        timer.cancel();
      }
    });
  }

  void _onTargetTap(Target target) {
    if (!isPlaying || isPaused) return;

    // Capture targetColor at the start to prevent race conditions
    // This ensures consistent validation even if targetColor changes during processing
    final currentTargetColor = targetColor;
    if (currentTargetColor == null) return; // No target color set yet

    // Find the target in the list by ID to ensure we're working with the correct one
    // This prevents race conditions where multiple taps happen or target is removed
    final targetIndex = targets.indexWhere((t) => t.id == target.id);
    if (targetIndex == -1) return; // Target already removed or doesn't exist

    final actualTarget = targets[targetIndex];
    final isCorrect = actualTarget.color == currentTargetColor;
    final tapPosition = Offset(
      actualTarget.position.dx,
      actualTarget.position.dy,
    );

    // Trigger crazy vibration and visual effects
    _triggerVibration(isCorrect);
    _triggerVisualEffect(isCorrect, tapPosition);

    setState(() {
      // Double-check target still exists before processing
      final checkIndex = targets.indexWhere((t) => t.id == target.id);
      if (checkIndex == -1) return; // Target was already removed by another tap

      if (isCorrect) {
        // Correct hit!
        score += (10 * level).toInt();
        final hitY = actualTarget.position.dy; // Get Y position before removing
        targets.removeAt(
          checkIndex,
        ); // Remove by index to ensure correct removal

        // Set new target color, avoiding colors that are below the hit target
        _setNewTargetColor(hitY);
      } else {
        // Wrong target - only remove if it still exists
        if (checkIndex != -1) {
          targets.removeAt(checkIndex);
        }
        lives--;
        if (lives <= 0) {
          _gameOver();
        }
      }

      if (score > highScore) {
        highScore = score;
      }
    });
  }

  void _gameOver() {
    gameTimer?.cancel();
    spawnTimer?.cancel();

    // Play game over vibration
    // Background music continues playing
    if (vibrationEnabled) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 100), () {
        HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 200), () {
        HapticFeedback.heavyImpact();
      });
    }

    setState(() {
      isPlaying = false;
      isPaused = false;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Game Over!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Final Score: $score'),
            Text('Level Reached: $level'),
            if (score == highScore && score > 0)
              const Text(
                '🎉 New High Score!',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              resetGame();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  void pauseGame() {
    setState(() {
      isPaused = !isPaused;
    });
    // Background music continues playing even when game is paused
  }

  void resetGame() {
    gameTimer?.cancel();
    spawnTimer?.cancel();

    // Background music continues playing
    setState(() {
      isPlaying = false;
      isPaused = false;
      score = 0;
      lives = 3;
      gameSpeed = 1.0;
      level = 1;
      targets.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raining Colors'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Game area
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.grey[900]!, Colors.grey[800]!],
              ),
            ),
            child: GestureDetector(
              behavior: HitTestBehavior
                  .translucent, // Allow taps through visual effects
              onTap: () {
                if (isPlaying && !isPaused) {
                  // Tap anywhere to pause
                  pauseGame();
                }
              },
              child: Transform.translate(
                offset: _shakeOffset,
                child: CustomPaint(
                  painter: showTrails ? TrailsPainter(targets) : null,
                  child: Stack(
                    children: [
                      // Targets
                      ...targets.map(
                        (target) => Positioned(
                          left: target.position.dx - target.size / 2,
                          top: target.position.dy - target.size / 2,
                          child: GestureDetector(
                            onTap: () => _onTargetTap(target),
                            child: Container(
                              width: target.size,
                              height: target.size,
                              decoration: BoxDecoration(
                                color: target.color,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: target.color.withValues(alpha: 0.5),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: showParticles
                                  ? CustomPaint(
                                      painter: ParticlePainter(target.color),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),

                      // Pulse effect - bigger and more visible
                      if (_pulsePosition != null)
                        Positioned(
                          left: _pulsePosition!.dx - _pulseRadius,
                          top: _pulsePosition!.dy - _pulseRadius,
                          child: IgnorePointer(
                            child: Container(
                              width: _pulseRadius * 2,
                              height: _pulseRadius * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(
                                    alpha: 1.0 - (_pulseRadius / 400),
                                  ),
                                  width: 5, // Thicker border
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(
                                      alpha: 0.5 * (1.0 - (_pulseRadius / 400)),
                                    ),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Particles - bigger and more visible
                      ..._particles.map(
                        (particle) => Positioned(
                          left: particle.position.dx - 6,
                          top: particle.position.dy - 6,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: particle.life,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: particle.color,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: particle.color.withValues(
                                        alpha: particle.life * 0.8,
                                      ),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Screen flash overlay - MUCH more intense
                      if (_flashColor != null)
                        IgnorePointer(
                          child: Container(
                            color: _flashColor!.withValues(
                              alpha: 0.6, // Much brighter flash
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // UI Overlay
          SafeArea(
            child: Column(
              children: [
                // Top stats bar
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatContainer(
                        Icons.star,
                        'Score',
                        score.toString(),
                        Colors.yellow,
                      ),
                      _buildStatContainer(
                        Icons.favorite,
                        'Lives',
                        lives.toString(),
                        Colors.red,
                      ),
                      _buildStatContainer(
                        Icons.trending_up,
                        'Level',
                        level.toString(),
                        Colors.green,
                      ),
                      _buildStatContainer(
                        Icons.emoji_events,
                        'Best',
                        highScore.toString(),
                        Colors.orange,
                      ),
                    ],
                  ),
                ),

                // Target color indicator
                if (isPlaying && targetColor != null)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'TARGET:   ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: targetColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: targetColor!.withValues(alpha: 0.5),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                const Spacer(),

                // Control buttons
                if (!isPlaying)
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        if (playerName.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person, color: Colors.blue),
                                const SizedBox(width: 8),
                                Text(
                                  'Welcome, $playerName!',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ElevatedButton.icon(
                          onPressed: startGame,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('START GAME'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 16,
                            ),
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (isPlaying && isPaused)
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: ElevatedButton.icon(
                      onPressed: pauseGame,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('RESUME'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 16,
                        ),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatContainer(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Game Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Player name TextField
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Player Name',
                        hintText: 'Enter your name',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          playerName = value;
                        });
                      },
                    ),
                    const SizedBox(height: 20),

                    // Difficulty RadioButtons
                    const Text(
                      'Difficulty:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    RadioListTile<String>(
                      title: const Text('Easy'),
                      value: 'Easy',
                      groupValue: difficulty,
                      onChanged: (value) {
                        setDialogState(() {
                          difficulty = value!;
                          _updateDifficulty();
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Medium'),
                      value: 'Medium',
                      groupValue: difficulty,
                      onChanged: (value) {
                        setDialogState(() {
                          difficulty = value!;
                          _updateDifficulty();
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Hard'),
                      value: 'Hard',
                      groupValue: difficulty,
                      onChanged: (value) {
                        setDialogState(() {
                          difficulty = value!;
                          _updateDifficulty();
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Extreme'),
                      value: 'Extreme',
                      groupValue: difficulty,
                      onChanged: (value) {
                        setDialogState(() {
                          difficulty = value!;
                          _updateDifficulty();
                        });
                      },
                    ),
                    const SizedBox(height: 20),

                    // Spawn Rate Slider
                    const Text(
                      'Spawn Rate:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Slider(
                      value: spawnRate,
                      min: 0.5,
                      max: 3.0,
                      divisions: 25,
                      label: '${spawnRate.toStringAsFixed(1)}s',
                      onChanged: (value) {
                        setDialogState(() {
                          spawnRate = value;
                        });
                      },
                    ),
                    const SizedBox(height: 20),

                    // Target Speed Slider
                    const Text(
                      'Target Speed:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Slider(
                      value: targetSpeed,
                      min: 1.0,
                      max: 5.0,
                      divisions: 40,
                      label: targetSpeed.toStringAsFixed(1),
                      onChanged: (value) {
                        setDialogState(() {
                          targetSpeed = value;
                        });
                      },
                    ),
                    const SizedBox(height: 20),

                    // Checkboxes
                    const Text(
                      'Game Options:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    CheckboxListTile(
                      title: const Text('Show Trails'),
                      value: showTrails,
                      onChanged: (value) {
                        setDialogState(() {
                          showTrails = value ?? false;
                        });
                      },
                    ),
                    CheckboxListTile(
                      title: const Text('Vibration'),
                      value: vibrationEnabled,
                      onChanged: (value) {
                        setDialogState(() {
                          vibrationEnabled = value ?? true;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      playerName = _nameController.text;
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class ParticlePainter extends CustomPainter {
  final Color color;

  ParticlePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 5; i++) {
      final angle = (i * 2 * pi) / 5;
      final radius = size.width / 3;
      final x = center.dx + cos(angle) * radius;
      final y = center.dy + sin(angle) * radius;
      canvas.drawCircle(Offset(x, y), 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TrailsPainter extends CustomPainter {
  final List<Target> targets;

  TrailsPainter(this.targets);

  @override
  void paint(Canvas canvas, Size size) {
    for (final target in targets) {
      final paint = Paint()
        ..color = target.color.withValues(alpha: 0.2)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(target.position.dx, target.position.dy);
      path.lineTo(target.position.dx, target.position.dy - 50);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
