/*
 * Copyright (c) 2021 Simform Solutions
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../models/tooltip_action_button.dart';
import '../models/tooltip_action_config.dart';
import '../utils/constants.dart';
import '../utils/enum.dart';
import '../utils/overlay_manager.dart';
import '../widget/floating_action_widget.dart';
import 'showcase_controller.dart';
import 'showcase_service.dart';

/// Callback type for showcase events that need index and key information
typedef OnShowcaseCallback = void Function(int? showcaseIndex, GlobalKey key);

/// Callback function type for building a floating action widget.
///
/// Parameters:
///   * [context] - The build context used to access the ShowcaseView state.
typedef FloatingActionBuilderCallback = FloatingActionWidget Function(
  BuildContext context,
);

/// Callback function type for handling showcase dismissal events.
///
/// This callback is triggered when a showcase is dismissed, providing the key
/// of the dismissed showcase widget if available.
typedef OnDismissCallback = void Function(
  /// The key on which showcase is dismissed. Null if no showcase was active.
  GlobalKey? dismissedAt,
);

class ShowcaseView {
  /// Creates and registers a [ShowcaseView] with the specified [scope].
  ///
  /// A controller class that manages showcase functionality independently.
  ///
  /// This class provides a way to manage showcase state and configure various
  /// options like auto-play, animation, and many more.
  ShowcaseView.register({
    this.scope = Constants.defaultScope,
    this.onFinish,
    this.onStart,
    this.onComplete,
    this.onDismiss,
    this.autoPlay = false,
    this.autoPlayDelay = Constants.defaultAutoPlayDelay,
    this.enableAutoPlayLock = false,
    this.blurValue = 0,
    this.scrollDuration = Constants.defaultScrollDuration,
    this.disableMovingAnimation = false,
    this.disableScaleAnimation = false,
    this.enableAutoScroll = false,
    this.disableBarrierInteraction = false,
    this.enableShowcase = true,
    this.globalTooltipActionConfig,
    this.globalTooltipActions,
    this.globalFloatingActionWidget,
    this.hideFloatingActionWidgetForShowcase = const [],
    Map<GlobalKey, bool>? skippableKeys,
  }) {
    ShowcaseService.instance.register(this, scope: scope);
    _hideFloatingWidgetKeys = {
      for (final item in hideFloatingActionWidgetForShowcase) item: true,
    };
    // Register skippable status for keys provided at registration
    if (skippableKeys != null) {
      _skippableKeys.addAll(skippableKeys);
    }
  }

  /// Retrieves last registered [ShowcaseView].
  factory ShowcaseView.get() => ShowcaseService.instance.get();

  /// Retrieves registered Showcase with the specified [scope].
  ///
  /// This is recommended to use when you have multiple scopes registered.
  factory ShowcaseView.getNamed(String scope) =>
      ShowcaseService.instance.get(scope: scope);

  /// The enclosing scope for this instance.
  final String scope;

  /// Triggered when all the showcases are completed.
  final VoidCallback? onFinish;

  /// Triggered when showcase view is dismissed.
  final OnDismissCallback? onDismiss;

  /// Triggered every time on start of each showcase.
  final OnShowcaseCallback? onStart;

  /// Triggered every time on completion of each showcase.
  final OnShowcaseCallback? onComplete;

  /// Whether all showcases will auto sequentially start
  /// having time interval of [autoPlayDelay].
  bool autoPlay;

  /// Visibility time of current showcase when [autoPlay] is enabled.
  Duration autoPlayDelay;

  /// Whether blocking user interaction while [autoPlay] is enabled.
  bool enableAutoPlayLock;

  /// Whether to disable bouncing/moving animation for all tooltips while
  /// showcasing.
  bool disableMovingAnimation;

  /// Whether to disable scale animation for all the default tooltips when
  /// showcase appears and goes away.
  bool disableScaleAnimation;

  /// Whether to disable barrier interaction.
  bool disableBarrierInteraction;

  /// Determines the time taken to scroll when [enableAutoScroll] is true.
  Duration scrollDuration;

  /// The overlay blur used by showcase.
  double blurValue;

  /// Whether to enable auto scroll as to bring the target widget in the
  /// viewport.
  bool enableAutoScroll;

  /// Enable/disable showcase globally.
  bool enableShowcase;

  /// Custom static floating action widget to show a static non-animating
  /// widget anywhere on the screen for all the showcase widget.
  FloatingActionBuilderCallback? globalFloatingActionWidget;

  /// Global action to show on every tooltip widget.
  List<TooltipActionButton>? globalTooltipActions;

  /// Global Config for tooltip action to auto apply for all the tooltip.
  TooltipActionConfig? globalTooltipActionConfig;

  /// Hides [globalFloatingActionWidget] for the provided showcase widgets.
  List<GlobalKey> hideFloatingActionWidgetForShowcase;

  /// Internal list to store showcase widget keys.
  List<GlobalKey>? _ids;

  /// Internal list to store partition showcase widget keys.
  /// Each inner list represents a partition of keys.
  List<List<GlobalKey>>? _partitionKeys;

  /// Current active showcase widget index.
  int? _activeWidgetId;

  /// Timer for auto-play functionality.
  Timer? _timer;

  /// Whether the manager is mounted and active.
  bool _mounted = true;

  /// Map to store keys for which floating action widget should be hidden.
  late final Map<GlobalKey, bool> _hideFloatingWidgetKeys;

  /// Map to store skippable status for each showcase key.
  final Map<GlobalKey, bool> _skippableKeys = {};

  /// Helper method to get formatted timestamp for logging
  String _getTimestamp() {
    final now = DateTime.now();
    return '[${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}]';
  }

  /// Helper method to convert a map to a readable string for logging
  String _mapToString(Map<dynamic, dynamic> map, {int indent = 0}) {
    if (map.isEmpty) return '{}';
    final indentStr = '  ' * (indent + 1);
    final buffer = StringBuffer();
    buffer.writeln('{');
    map.forEach((key, value) {
      String valueStr;
      if (value == null) {
        valueStr = 'null';
      } else if (value is Map) {
        valueStr = '\n${_mapToString(Map<dynamic, dynamic>.from(value), indent: indent + 1)}';
      } else if (value is List) {
        if (value.isEmpty) {
          valueStr = '[]';
        } else if (value.length <= 3) {
          valueStr = '[${value.join(", ")}]';
        } else {
          // For longer lists, show first few and count
          valueStr = '[${value.take(3).join(", ")}, ... (${value.length} total)]';
        }
      } else {
        valueStr = value.toString();
      }
      buffer.writeln('$indentStr$key: $valueStr');
    });
    buffer.write('  ' * indent + '}');
    return buffer.toString();
  }

  /// Helper method to get a summary of which keys are found and not found
  Map<String, dynamic> _getKeyStatusSummary() {
    if (_ids == null || _ids!.isEmpty) {
      return {
        'total_keys': 0,
        'found_keys': <String>[],
        'not_found_keys': <String>[],
        'all_keys': <String>[],
        'checking_scope': scope,
        'registered_keys_in_service': <String>[],
      };
    }

    final allControllers = ShowcaseService.instance.getControllers(scope: scope);
    final foundKeys = <String>[];
    final notFoundKeys = <String>[];
    final allKeys = <String>[];
    final registeredKeysInService = <String>[];
    final keyDiagnostics = <Map<String, dynamic>>[];

    // Get all keys registered in ShowcaseService for this scope
    for (final registeredKey in allControllers.keys) {
      registeredKeysInService.add(registeredKey.toString());
    }

    for (int i = 0; i < _ids!.length; i++) {
      final key = _ids![i];
      final keyStr = '[$i] ${key.toString()}';
      allKeys.add(keyStr);
      
      final controllers = allControllers[key];
      final hasControllers = controllers != null && controllers.isNotEmpty;
      final hasContext = key.currentContext != null;
      final isRegisteredInService = allControllers.containsKey(key);
      
      final diagnostic = {
        'index': i,
        'key': key.toString(),
        'has_controllers': hasControllers,
        'controller_count': controllers?.length ?? 0,
        'has_widget_in_tree': hasContext,
        'is_registered_in_service': isRegisteredInService,
        'context_info': hasContext 
            ? 'Widget is in tree (context exists)'
            : 'Widget NOT in tree (context is null - may be disposed or not built yet)',
      };
      keyDiagnostics.add(diagnostic);
      
      if (hasControllers) {
        foundKeys.add(keyStr);
      } else {
        notFoundKeys.add(keyStr);
      }
    }

    return {
      'total_keys': _ids!.length,
      'found_count': foundKeys.length,
      'not_found_count': notFoundKeys.length,
      'found_keys': foundKeys,
      'not_found_keys': notFoundKeys,
      'all_keys': allKeys,
      'checking_scope': scope,
      'registered_keys_in_service': registeredKeysInService,
      'registered_keys_count': registeredKeysInService.length,
      'key_diagnostics': keyDiagnostics,
    };
  }

  /// Returns whether showcase is completed or not.
  bool get isShowCaseCompleted => _ids == null && _activeWidgetId == null;

  /// Returns list of keys for which floating action widget is hidden.
  List<GlobalKey> get hiddenFloatingActionKeys =>
      _hideFloatingWidgetKeys.keys.toList();

  /// Returns the current active showcase key if any.
  GlobalKey? get getActiveShowcaseKey {
    if (_ids == null || _activeWidgetId == null) return null;

    if (_activeWidgetId! < _ids!.length && _activeWidgetId! >= 0) {
      return _ids![_activeWidgetId!];
    } else {
      return null;
    }
  }

  /// Returns whether showcase is currently running or not.
  bool get isShowcaseRunning => getActiveShowcaseKey != null;

  /// Checks if a key is actually skipped (skippable and not found in widget tree).
  ///
  /// * [key] - The key to check
  /// Returns true if the key is skippable and doesn't have controllers.
  bool _isKeySkipped(GlobalKey key) {
    if (!isSkippable(key)) return false;
    final controllers = ShowcaseService.instance
        .getControllers(scope: scope)[key];
    return controllers == null || controllers.isEmpty;
  }

  /// Returns the current step index (0-based) if showcase is running.
  ///
  /// Returns null if showcase is not running or completed.
  /// If skippableKeys are present, returns the index excluding skipped keys.
  /// If partition keys are present, returns the index within the partition list
  /// that the current key belongs to.
  int? get currentStepIndex {
    if (_ids == null || _activeWidgetId == null) {
      developer.log('${_getTimestamp()} 🔍 [SHOWCASE] currentStepIndex - No IDs or activeWidgetId', name: 'ShowcaseView');
      return null;
    }
    if (_activeWidgetId! < 0 || _activeWidgetId! >= _ids!.length) {
      developer.log(
        '${_getTimestamp()} 🔍 [SHOWCASE] currentStepIndex - Invalid activeWidgetId\n${_mapToString({
          'active_index': _activeWidgetId,
          'total_steps': _ids!.length,
        })}',
        name: 'ShowcaseView',
      );
      return null;
    }
    
    final currentKey = _ids![_activeWidgetId!];
    
    // If partition keys are present, calculate index within the relevant partition
    if (_partitionKeys != null) {
      // Find which partition list the current key belongs to
      // Use identity comparison to ensure we find the exact key reference
      List<GlobalKey>? currentPartition;
      int partitionIndex = -1;
      for (int pIdx = 0; pIdx < _partitionKeys!.length; pIdx++) {
        final partition = _partitionKeys![pIdx];
        // Check if currentKey is in this partition using identity
        for (final key in partition) {
          if (identical(key, currentKey) || key == currentKey) {
            currentPartition = partition;
            partitionIndex = pIdx;
            break;
          }
        }
        if (currentPartition != null) break;
      }
      
      if (currentPartition != null) {
        // Find index within this partition
        int displayedIndex = 0;
        for (int i = 0; i < _activeWidgetId!; i++) {
          final key = _ids![i];
          // Check if key is in current partition using identity
          bool isInPartition = false;
          for (final partitionKey in currentPartition) {
            if (identical(key, partitionKey) || key == partitionKey) {
              isInPartition = true;
              break;
            }
          }
          if (isInPartition && !_isKeySkipped(key)) {
            displayedIndex++;
          }
        }
        
        developer.log(
          '${_getTimestamp()} 📊 [SHOWCASE] currentStepIndex - Partition mode\n${_mapToString({
            'active_index': _activeWidgetId,
            'partition_index': partitionIndex,
            'partition_size': currentPartition.length,
            'displayed_index': displayedIndex,
            'has_skippable': _skippableKeys.isNotEmpty,
          })}',
          name: 'ShowcaseView',
        );
        
        return displayedIndex;
      } else {
        developer.log(
          '${_getTimestamp()} ⚠️ [SHOWCASE] currentStepIndex - Partition not found for key\n${_mapToString({
            'active_index': _activeWidgetId,
            'current_key': currentKey.toString(),
            'partition_count': _partitionKeys!.length,
          })}',
          name: 'ShowcaseView',
        );
      }
    }
    
    // If no skippable keys, return the raw index
    if (_skippableKeys.isEmpty) {
      developer.log(
        '${_getTimestamp()} 📊 [SHOWCASE] currentStepIndex - No partitions, no skippable\n${_mapToString({
          'active_index': _activeWidgetId,
          'returned_index': _activeWidgetId,
        })}',
        name: 'ShowcaseView',
      );
      return _activeWidgetId;
    }
    
    // Count non-skipped keys before the current active widget
    int displayedIndex = 0;
    for (int i = 0; i < _activeWidgetId!; i++) {
      if (!_isKeySkipped(_ids![i])) {
        displayedIndex++;
      }
    }
    
    developer.log(
      '${_getTimestamp()} 📊 [SHOWCASE] currentStepIndex - With skippable\n${_mapToString({
        'active_index': _activeWidgetId,
        'displayed_index': displayedIndex,
        'skippable_count': _skippableKeys.length,
      })}',
      name: 'ShowcaseView',
    );
    
    return displayedIndex;
  }

  /// Returns the total number of steps in the showcase.
  /// If skippableKeys are present, returns the count excluding skipped keys.
  /// If partition keys are present and showcase is running, returns the total
  /// of only the partition list that the current key belongs to.
  int get totalSteps {
    if (_ids == null) {
      developer.log('${_getTimestamp()} 🔍 [SHOWCASE] totalSteps - No IDs', name: 'ShowcaseView');
      return 0;
    }
    
    // If partition keys are present, try to find the current partition
    if (_partitionKeys != null) {
      // If showcase is running, find partition based on current key
      if (_activeWidgetId != null && _activeWidgetId! >= 0 && _activeWidgetId! < _ids!.length) {
        final currentKey = _ids![_activeWidgetId!];
        
        // Find which partition list the current key belongs to
        // Use identity comparison to ensure we find the exact key reference
        List<GlobalKey>? currentPartition;
        int partitionIndex = -1;
        for (int pIdx = 0; pIdx < _partitionKeys!.length; pIdx++) {
          final partition = _partitionKeys![pIdx];
          // Check if currentKey is in this partition using identity
          for (final key in partition) {
            if (identical(key, currentKey) || key == currentKey) {
              currentPartition = partition;
              partitionIndex = pIdx;
              break;
            }
          }
          if (currentPartition != null) break;
        }
        
        if (currentPartition != null) {
          // Count only non-skipped keys in this partition
          if (_skippableKeys.isEmpty) {
            developer.log(
              '${_getTimestamp()} 📊 [SHOWCASE] totalSteps - Partition mode (no skippable)\n${_mapToString({
                'active_index': _activeWidgetId,
                'partition_index': partitionIndex,
                'partition_size': currentPartition.length,
                'total_steps': currentPartition.length,
                'all_partitions': _partitionKeys!.map((p) => p.length).toList(),
              })}',
              name: 'ShowcaseView',
            );
            return currentPartition.length;
          }
          int skippedCount = 0;
          for (final key in currentPartition) {
            if (_isKeySkipped(key)) {
              skippedCount++;
            }
          }
          final total = currentPartition.length - skippedCount;
          developer.log(
            '${_getTimestamp()} 📊 [SHOWCASE] totalSteps - Partition mode (with skippable)\n${_mapToString({
              'active_index': _activeWidgetId,
              'partition_index': partitionIndex,
              'partition_size': currentPartition.length,
              'skipped_count': skippedCount,
              'total_steps': total,
              'all_partitions': _partitionKeys!.map((p) => p.length).toList(),
            })}',
            name: 'ShowcaseView',
          );
          return total;
        } else {
          developer.log(
            '${_getTimestamp()} ⚠️ [SHOWCASE] totalSteps - Partition not found, returning 0\n${_mapToString({
              'active_index': _activeWidgetId,
              'current_key': currentKey.toString(),
              'partition_count': _partitionKeys!.length,
              'all_partitions': _partitionKeys!.map((p) => p.length).toList(),
            })}',
            name: 'ShowcaseView',
          );
        }
      } else {
        developer.log(
          '${_getTimestamp()} ⚠️ [SHOWCASE] totalSteps - Invalid activeWidgetId for partition\n${_mapToString({
            'active_index': _activeWidgetId,
            'total_steps': _ids!.length,
            'partition_count': _partitionKeys!.length,
          })}',
          name: 'ShowcaseView',
        );
      }
      
      // If partitions are provided but we can't determine current partition,
      // this shouldn't happen if validation passed, but return 0 to avoid
      // showing incorrect total. This ensures we don't fall back to full total
      // when partitions exist.
      return 0;
    }
    
    // If no partition keys, return total of all keys
    // If no skippable keys, return the total length
    if (_skippableKeys.isEmpty) {
      developer.log(
        '${_getTimestamp()} 📊 [SHOWCASE] totalSteps - No partitions, no skippable\n${_mapToString({
          'total_steps': _ids!.length,
        })}',
        name: 'ShowcaseView',
      );
      return _ids!.length;
    }
    
    // Count only non-skipped keys (subtract skipped keys from total)
    int skippedCount = 0;
    for (final key in _ids!) {
      if (_isKeySkipped(key)) {
        skippedCount++;
      }
    }
    final total = _ids!.length - skippedCount;
    developer.log(
      '${_getTimestamp()} 📊 [SHOWCASE] totalSteps - No partitions, with skippable\n${_mapToString({
        'total_steps': _ids!.length,
        'skipped_count': skippedCount,
        'returned_total': total,
      })}',
      name: 'ShowcaseView',
    );
    return total;
  }

  /// Returns list of showcase controllers for current active showcase.
  List<ShowcaseController> get _getCurrentActiveControllers {
    return ShowcaseService.instance
            .getControllers(
              scope: scope,
            )[getActiveShowcaseKey]
            ?.values
            .toList() ??
        <ShowcaseController>[];
  }

  /// Starts showcase with given widget ids after the optional delay.
  ///
  /// * [widgetIds] - List of GlobalKeys for widgets to showcase
  /// * [partitionKeys] - Optional list of lists, where each inner list represents
  ///   a partition of showcase widget keys
  /// * [delay] - Optional delay before starting showcase
  ///
  /// If [partitionKeys] is provided, it validates that concatenating all lists
  /// in [partitionKeys] equals [widgetIds]. If not the same, throws an assertion error.
  /// When partition keys are provided, the total steps and current step index
  /// are calculated based on which partition list the current key belongs to.
  void startShowCase(
    List<GlobalKey> widgetIds, {
    List<List<GlobalKey>>? partitionKeys,
    Duration delay = Duration.zero,
  }) {
    assert(_mounted, 'ShowcaseView is no longer mounted');
    if (!_mounted) return;
    
    developer.log(
      '${_getTimestamp()} 🎬 [SHOWCASE] startShowCase called\n${_mapToString({
        'widgetIds_count': widgetIds.length,
        'partitionKeys_count': partitionKeys?.length ?? 0,
        'delay': delay.inMilliseconds,
        'scope': scope,
      })}',
      name: 'ShowcaseView',
    );
    
    // If partition keys are provided, validate that all partitions concatenated = widgetIds
    if (partitionKeys != null && partitionKeys.isNotEmpty) {
      // Flatten all partition lists
      final combinedKeys = <GlobalKey>[];
      for (final partition in partitionKeys) {
        combinedKeys.addAll(partition);
      }
      
      developer.log(
        '${_getTimestamp()} 📊 [SHOWCASE] Partition validation\n${_mapToString({
          'total_keys': widgetIds.length,
          'combined_partition_keys': combinedKeys.length,
          'partition_count': partitionKeys.length,
          'partitions': partitionKeys.map((p) => p.length).toList(),
        })}',
        name: 'ShowcaseView',
      );
      
      assert(
        combinedKeys.length == widgetIds.length,
        'The concatenation of all partitionKeys must equal widgetIds. '
        'Expected ${widgetIds.length} keys, but got ${combinedKeys.length}',
      );
      
      // Check that the order and content match
      for (int i = 0; i < widgetIds.length; i++) {
        assert(
          combinedKeys[i] == widgetIds[i],
          'Key mismatch at index $i: expected ${widgetIds[i]}, but got ${combinedKeys[i]}',
        );
      }
      
      // Store partition keys (deep copy)
      _partitionKeys = partitionKeys.map((list) => List<GlobalKey>.from(list)).toList();
      
      developer.log(
        '${_getTimestamp()} ✅ [SHOWCASE] Partitions stored\n${_mapToString({
          'partition_count': _partitionKeys!.length,
          'partitions': _partitionKeys!.map((p) => p.length).toList(),
        })}',
        name: 'ShowcaseView',
      );
    } else {
      // No partition keys, clear them
      _partitionKeys = null;
      developer.log('${_getTimestamp()} ℹ️ [SHOWCASE] No partitions provided', name: 'ShowcaseView');
    }
    
    _findEnclosingShowcaseView(widgetIds)._startShowcase(delay, widgetIds);
  }

  /// Moves to next showcase if possible.
  ///
  /// Will finish entire showcase if no more widgets to show.
  ///
  /// * [force] - Whether to ignore autoPlayLock, defaults to false.
  void next({bool force = false}) {
    if ((!force && enableAutoPlayLock) || _ids == null || !_mounted) {
      return;
    }
    _changeSequence(ShowcaseProgressType.forward);
  }

  /// Moves to previous showcase if possible.
  ///
  /// Does nothing if already at the first showcase.
  void previous() {
    if (_ids == null || ((_activeWidgetId ?? 0) - 1).isNegative || !_mounted) {
      return;
    }
    _changeSequence(ShowcaseProgressType.backward);
  }

  /// Completes showcase for given key and starts next one.
  ///
  /// * [key] - The key of the showcase to complete.
  ///
  /// Will finish entire showcase if no more widgets to show.
  void completed(GlobalKey? key) {
    developer.log(
      '${_getTimestamp()} ✅ [SHOWCASE] completed called\n${_mapToString({
        'key': key?.toString(),
        'active_index': _activeWidgetId,
        'active_key': _activeWidgetId != null && _ids != null && _activeWidgetId! < _ids!.length
            ? _ids![_activeWidgetId!].toString()
            : null,
        'mounted': _mounted,
        'current_step_index': currentStepIndex,
        'total_steps': totalSteps,
      })}',
      name: 'ShowcaseView',
    );
    
    if (_activeWidgetId == null ||
        _ids?[_activeWidgetId!] != key ||
        !_mounted) {
      developer.log(
        '${_getTimestamp()} ⚠️ [SHOWCASE] completed - Conditions not met, ignoring\n${_mapToString({
          'active_index_null': _activeWidgetId == null,
          'key_mismatch': _ids?[_activeWidgetId ?? -1] != key,
          'not_mounted': !_mounted,
        })}',
        name: 'ShowcaseView',
      );
      return;
    }
    _changeSequence(ShowcaseProgressType.forward);
  }

  /// Dismisses the entire showcase and calls [onDismiss] callback.
  void dismiss() {
    final idDoesNotExist =
        _activeWidgetId == null || (_ids?.length ?? -1) <= _activeWidgetId!;

    developer.log(
      '${_getTimestamp()} 🚫 [SHOWCASE] dismiss called\n${_mapToString({
        'active_index': _activeWidgetId,
        'id_does_not_exist': idDoesNotExist,
        'dismissed_key': idDoesNotExist || _activeWidgetId == null || _ids == null
            ? null
            : (_activeWidgetId! < _ids!.length ? _ids![_activeWidgetId!].toString() : null),
        'current_step_index': currentStepIndex,
        'total_steps': totalSteps,
        'mounted': _mounted,
      })}',
      name: 'ShowcaseView',
    );

    onDismiss?.call(idDoesNotExist ? null : _ids?[_activeWidgetId!]);
    if (!_mounted) {
      developer.log('${_getTimestamp()} ⚠️ [SHOWCASE] dismiss - Not mounted, aborting', name: 'ShowcaseView');
      return;
    }

    _cleanupAfterSteps();
    OverlayManager.instance.update(
      show: isShowcaseRunning,
      scope: scope,
    );
  }

  /// Cleans up resources when unregistering the showcase view.
  void unregister() {
    if (isShowcaseRunning) {
      OverlayManager.instance.dispose(scope: scope);
    }
    ShowcaseService.instance.unregister(scope: scope);
    _mounted = false;
    _cancelTimer();
  }

  /// Updates the overlay to reflect current showcase state.
  void updateOverlay() =>
      OverlayManager.instance.update(show: isShowcaseRunning, scope: scope);

  /// Updates list of showcase keys that should hide floating action widget.
  ///
  /// * [updatedList] - New list of keys to hide floating action widget for
  void hideFloatingActionWidgetForKeys(List<GlobalKey> updatedList) {
    _hideFloatingWidgetKeys
      ..clear()
      ..addAll({
        for (final item in updatedList) item: true,
      });
  }

  /// Returns floating action widget for given showcase key if not hidden.
  ///
  /// * [showcaseKey] - The key of the showcase to check.
  FloatingActionBuilderCallback? getFloatingActionWidget(
    GlobalKey showcaseKey,
  ) {
    return _hideFloatingWidgetKeys[showcaseKey] ?? false
        ? null
        : globalFloatingActionWidget;
  }

  /// Registers the skippable status for a showcase key.
  ///
  /// * [showcaseKey] - The key of the showcase
  /// * [skippable] - Whether this showcase should be skipped if not found
  void registerSkippable(GlobalKey showcaseKey, bool skippable) {
    _skippableKeys[showcaseKey] = skippable;
  }

  /// Checks if a showcase key is skippable.
  ///
  /// * [showcaseKey] - The key of the showcase to check
  /// Returns true if the showcase should be skipped when not found, false otherwise.
  bool isSkippable(GlobalKey showcaseKey) {
    // Check the stored map for skippable status
    return _skippableKeys[showcaseKey] ?? false;
  }

  void _startShowcase(
    Duration delay,
    List<GlobalKey<State<StatefulWidget>>> widgetIds,
  ) {
    assert(
      enableShowcase,
      'You are trying to start Showcase while it has been disabled with '
      '[enableShowcase] parameter.',
    );
    if (!enableShowcase) {
      developer.log('${_getTimestamp()} ⚠️ [SHOWCASE] Showcase disabled, not starting', name: 'ShowcaseView');
      return;
    }

    ShowcaseService.instance.updateCurrentScope(scope);
    if (delay == Duration.zero) {
      _ids = widgetIds;
      _activeWidgetId = 0;
      
      developer.log(
        '${_getTimestamp()} 🚀 [SHOWCASE] _startShowcase - Starting showcase\n${_mapToString({
          'total_steps': widgetIds.length,
          'active_index': _activeWidgetId,
          'has_partitions': _partitionKeys != null,
          'partition_count': _partitionKeys?.length ?? 0,
          'scope': scope,
        })}',
        name: 'ShowcaseView',
      );
      
      _onStart();
      OverlayManager.instance.update(
        show: isShowcaseRunning,
        scope: scope,
      );



































    } else {
      developer.log(
        '${_getTimestamp()} ⏳ [SHOWCASE] Delaying start by ${delay.inMilliseconds}ms',
        name: 'ShowcaseView',
      );
      Future.delayed(delay, () => _startShowcase(Duration.zero, widgetIds));
    }
  }

  /// Process showcase update after navigation
  ///
  /// This method handles the common logic needed when navigating between
  /// showcases:
  /// - Starts the current showcase
  /// - Checks if we've reached the end of showcases
  /// - Updates the overlay to reflect current state
  /// - Skips showcases that don't have their key in the widget tree
  ///   (if per-key skippable is enabled)
  void _changeSequence(ShowcaseProgressType type) {
    assert(_activeWidgetId != null, 'Please ensure to call startShowcase.');
    final id = switch (type) {
      ShowcaseProgressType.forward => _activeWidgetId! + 1,
      ShowcaseProgressType.backward => _activeWidgetId! - 1,
    };
    
    developer.log(
      '${_getTimestamp()} 🔄 [SHOWCASE] _changeSequence - ${type.name}\n${_mapToString({
        'current_index': _activeWidgetId,
        'next_index': id,
        'total_steps': _ids?.length ?? 0,
        'direction': type.name,
      })}',
      name: 'ShowcaseView',
    );
    
    _onComplete().then(
          (_) async {
        if (!_mounted) {
          developer.log('${_getTimestamp()} ⚠️ [SHOWCASE] Not mounted, aborting sequence change', name: 'ShowcaseView');
          return;
        }
        _activeWidgetId = id;
        
        developer.log(
          '${_getTimestamp()} 📍 [SHOWCASE] Active index set to $id\n${_mapToString({
            'active_index': _activeWidgetId,
            'total_steps': _ids?.length ?? 0,
          })}',
          name: 'ShowcaseView',
        );
        
        // Skip showcases that don't have their key in the widget tree
        // Check per-key skippable status
        _skipInvalidShowcases(type);
        await _onStart();
        // Check if showcase was finished in _onStart() or if we've reached the end
        if (!_mounted || _activeWidgetId == null || _activeWidgetId! >= _ids!.length || _activeWidgetId! < 0) {
          developer.log(
            '${_getTimestamp()} 🏁 [SHOWCASE] Showcase finished or reached end\n${_mapToString({
              'mounted': _mounted,
              'active_index': _activeWidgetId,
              'total_steps': _ids?.length ?? 0,
            })}',
            name: 'ShowcaseView',
          );
          // Showcase finished in _onStart() or reached the end
          return;
        }
        OverlayManager.instance.update(show: isShowcaseRunning, scope: scope);
      },
    );
  }

  /// Skips showcases that don't have their key in the widget tree.
  ///
  /// This method recursively checks if the current showcase has controllers
  /// (meaning its key exists in the widget tree). If not, it checks the skippable
  /// status for that key. If skippable is true, it automatically moves to the
  /// next/previous showcase until it finds one that exists or reaches the end
  /// of the showcase list. If skippable is false, it stops (pauses).
  ///
  /// * [type] - Direction to skip (forward or backward)
  /// * [maxIterations] - Maximum number of iterations to prevent infinite loops
  void _skipInvalidShowcases(ShowcaseProgressType type, {int maxIterations = 100}) {
    if (_ids == null || _activeWidgetId == null) {
      developer.log('${_getTimestamp()} ⚠️ [SHOWCASE] _skipInvalidShowcases - No IDs or activeWidgetId', name: 'ShowcaseView');
      return;
    }
    
    int iterations = 0;
    int skippedCount = 0;
    
    final keyStatus = _getKeyStatusSummary();
    developer.log(
      '${_getTimestamp()} 🔍 [SHOWCASE] _skipInvalidShowcases - Starting check\n${_mapToString({
        'start_index': _activeWidgetId,
        'direction': type.name,
        'total_steps': _ids!.length,
        'checking_scope': keyStatus['checking_scope'],
        'key_status': {
          'total_keys': keyStatus['total_keys'],
          'found_count': keyStatus['found_count'],
          'not_found_count': keyStatus['not_found_count'],
          'registered_keys_in_service_count': keyStatus['registered_keys_count'],
          'registered_keys_in_service': keyStatus['registered_keys_in_service'],
          'key_diagnostics': keyStatus['key_diagnostics'],
        },
      })}',
      name: 'ShowcaseView',
    );
    
    while (iterations < maxIterations) {
      // Check if we've reached the end
      if (_activeWidgetId! >= _ids!.length || _activeWidgetId! < 0) {
        developer.log(
          '${_getTimestamp()} 🏁 [SHOWCASE] Reached end of showcase list\n${_mapToString({
            'active_index': _activeWidgetId,
            'total_steps': _ids!.length,
            'skipped_count': skippedCount,
          })}',
          name: 'ShowcaseView',
        );
        break;
      }

      final currentKey = _ids![_activeWidgetId!];
      
      // Check if current showcase has controllers (key exists in widget tree)
      final controllers = _getCurrentActiveControllers;
      
      // Get diagnostic info for current key
      final currentKeyDiagnostic = (keyStatus['key_diagnostics'] as List)
          .firstWhere(
            (d) => d['index'] == _activeWidgetId,
            orElse: () => {'key': currentKey.toString(), 'error': 'Diagnostic not found'},
          );
      
      developer.log(
        '${_getTimestamp()} 🔎 [SHOWCASE] Checking key at index ${_activeWidgetId}\n${_mapToString({
          'index': _activeWidgetId,
          'key': currentKey.toString(),
          'has_controllers': controllers.isNotEmpty,
          'controller_count': controllers.length,
          'is_skippable': isSkippable(currentKey),
          'checking_scope': keyStatus['checking_scope'],
          'diagnostic': currentKeyDiagnostic,
        })}',
        name: 'ShowcaseView',
      );
      
      if (controllers.isNotEmpty) {
        // Found a valid showcase, stop skipping
        if (skippedCount > 0) {
          developer.log(
            '${_getTimestamp()} ✅ [SHOWCASE] Found valid showcase after skipping $skippedCount\n${_mapToString({
              'final_index': _activeWidgetId,
              'skipped_count': skippedCount,
            })}',
            name: 'ShowcaseView',
          );
        }
        break;
      }

      // Current showcase doesn't exist, check if it's skippable
      final shouldSkip = isSkippable(currentKey);
      
      if (!shouldSkip) {
        // Not skippable, stop here (will pause)
        // Get diagnostic info for current key
        final currentKeyDiagnostic = (keyStatus['key_diagnostics'] as List)
            .firstWhere(
              (d) => d['index'] == _activeWidgetId,
              orElse: () => {'key': currentKey.toString(), 'error': 'Diagnostic not found'},
            );
        developer.log(
          '${_getTimestamp()} ⏸️ [SHOWCASE] Key not found for $currentKey and NOT skippable - PAUSING\n${_mapToString({
            'index': _activeWidgetId,
            'key': currentKey.toString(),
            'action': 'PAUSE',
            'checking_scope': keyStatus['checking_scope'],
            'current_key_diagnostic': currentKeyDiagnostic,
            'key_status': {
              'total_keys': keyStatus['total_keys'],
              'found_count': keyStatus['found_count'],
              'not_found_count': keyStatus['not_found_count'],
              'registered_keys_in_service_count': keyStatus['registered_keys_count'],
              'registered_keys_in_service': keyStatus['registered_keys_in_service'],
              'not_found_keys': keyStatus['not_found_keys'],
              'found_keys': keyStatus['found_keys'],
            },
          })}',
          name: 'ShowcaseView',
        );
        break;
      }

      // Current showcase is skippable, skip to next/previous
      // Get diagnostic info for current key (reuse the one we already got above)
      final skipKeyDiagnostic = (keyStatus['key_diagnostics'] as List)
          .firstWhere(
            (d) => d['index'] == _activeWidgetId,
            orElse: () => {'key': currentKey.toString(), 'error': 'Diagnostic not found'},
          );
      developer.log(
        '${_getTimestamp()} ⏭️ [SHOWCASE] Key not found for $currentKey but SKIPPABLE - Skipping\n${_mapToString({
          'index': _activeWidgetId,
          'key': currentKey.toString(),
          'action': 'SKIP',
          'checking_scope': keyStatus['checking_scope'],
          'current_key_diagnostic': skipKeyDiagnostic,
          'key_status': {
            'total_keys': keyStatus['total_keys'],
            'found_count': keyStatus['found_count'],
            'not_found_count': keyStatus['not_found_count'],
            'registered_keys_in_service_count': keyStatus['registered_keys_count'],
            'registered_keys_in_service': keyStatus['registered_keys_in_service'],
            'not_found_keys': keyStatus['not_found_keys'],
            'found_keys': keyStatus['found_keys'],
          },
        })}',
        name: 'ShowcaseView',
      );
      
      final nextId = switch (type) {
        ShowcaseProgressType.forward => _activeWidgetId! + 1,
        ShowcaseProgressType.backward => _activeWidgetId! - 1,
      };

      // Check bounds
      if (nextId >= _ids!.length || nextId < 0) {
        developer.log(
          '${_getTimestamp()} 🏁 [SHOWCASE] Reached bounds, stopping skip\n${_mapToString({
            'next_index': nextId,
            'total_steps': _ids!.length,
            'skipped_count': skippedCount,
          })}',
          name: 'ShowcaseView',
        );
        break;
      }

      _activeWidgetId = nextId;
      skippedCount++;
      iterations++;
    }
    
    if (iterations >= maxIterations) {
      developer.log(
        '${_getTimestamp()} ⚠️ [SHOWCASE] Max iterations reached in _skipInvalidShowcases\n${_mapToString({
          'iterations': iterations,
          'skipped_count': skippedCount,
        })}',
        name: 'ShowcaseView',
      );
    }
  }

  /// Finds the appropriate ShowcaseView that can handle all the specified
  /// widget keys.
  ///
  /// This method searches through all registered scopes to find a
  /// [ShowcaseView] that contains all the widget keys in [widgetIds]. This
  /// is necessary when starting a showcase that might include widgets
  /// registered across different scopes.
  ///
  /// * [widgetIds] - List of GlobalKeys for widgets to showcase
  ///
  /// Returns either the current ShowcaseView if all keys are in this scope, or
  /// another scope's ShowcaseView that contains the keys not found in the
  /// current scope.
  ShowcaseView _findEnclosingShowcaseView(
      List<GlobalKey<State<StatefulWidget>>> widgetIds,
      ) {
    final currentScopeControllers =
    ShowcaseService.instance.getControllers(scope: scope);
    final keysNotInCurrentScope = {
      for (final key in widgetIds)
        if (!currentScopeControllers.containsKey(key)) key: true,
    };

    if (keysNotInCurrentScope.isEmpty) return this;

    final scopes = ShowcaseService.instance.scopes;
    final scopeLength = scopes.length;
    for (var i = 0; i < scopeLength; i++) {
      final otherScopeName = scopes[i];
      if (otherScopeName == scope || otherScopeName == Constants.initialScope) {
        continue;
      }

      final otherScope = ShowcaseService.instance.getScope(
        scope: otherScopeName,
      );
      final otherScopeControllers = otherScope.controllers;

      if (otherScopeControllers.keys.any(keysNotInCurrentScope.containsKey)) {
        return otherScope.showcaseView;
      }
    }
    return this;
  }

  /// Internal method to handle showcase start.
  ///
  /// Initializes controllers and sets up auto-play timer if enabled.
  /// Skips showcases that don't have their key in the widget tree
  /// (if per-key skippable is enabled).
  Future<void> _onStart() async {
    _activeWidgetId ??= 0;
    
    developer.log(
      '${_getTimestamp()} ▶️ [SHOWCASE] _onStart - Starting step\n${_mapToString({
        'active_index': _activeWidgetId,
        'total_steps': _ids?.length ?? 0,
        'current_step_index': currentStepIndex,
        'total_steps_calculated': totalSteps,
        'has_partitions': _partitionKeys != null,
      })}',
      name: 'ShowcaseView',
    );
    
    // Skip showcases that don't have their key in the widget tree
    // Check per-key skippable status
    _skipInvalidShowcases(ShowcaseProgressType.forward);
    
    // Check if we've reached the end after skipping
    if (_activeWidgetId! >= _ids!.length || _activeWidgetId! < 0) {
      developer.log(
        '${_getTimestamp()} 🏁 [SHOWCASE] _onStart - Reached end, finishing\n${_mapToString({
          'active_index': _activeWidgetId,
          'total_steps': _ids!.length,
        })}',
        name: 'ShowcaseView',
      );
      _cleanupAfterSteps();
      OverlayManager.instance.update(show: false, scope: scope);
      onFinish?.call();
      return;
    }
    
    final controllers = _getCurrentActiveControllers;
    final currentKey = _ids![_activeWidgetId!];
    
    developer.log(
      '${_getTimestamp()} 🔍 [SHOWCASE] _onStart - Checking controllers\n${_mapToString({
        'active_index': _activeWidgetId,
        'current_key': currentKey.toString(),
        'controller_count': controllers.length,
        'is_skippable': isSkippable(currentKey),
      })}',
      name: 'ShowcaseView',
    );
    
    // If no controllers found, check if we should pause or skip
    if (controllers.isEmpty) {
      final shouldSkip = isSkippable(currentKey);
      
      if (!shouldSkip) {
        // Not skippable, pause (keep showcase active but don't show anything)
        // The showcase will continue when the widget appears and recalculateRootWidgetSize
        // is called, which will trigger updateControllerData and overlay update
        final keyStatus = _getKeyStatusSummary();
        // Get diagnostic info for current key
        final currentKeyDiagnostic = (keyStatus['key_diagnostics'] as List)
            .firstWhere(
              (d) => d['index'] == _activeWidgetId,
              orElse: () => {'key': currentKey.toString(), 'error': 'Diagnostic not found'},
            );
        developer.log(
          '${_getTimestamp()} ⏸️ [SHOWCASE] _onStart - No controllers, NOT skippable - PAUSING\n${_mapToString({
            'active_index': _activeWidgetId,
            'current_key': currentKey.toString(),
            'action': 'PAUSE',
            'checking_scope': keyStatus['checking_scope'],
            'current_key_diagnostic': currentKeyDiagnostic,
            'key_status': {
              'total_keys': keyStatus['total_keys'],
              'found_count': keyStatus['found_count'],
              'not_found_count': keyStatus['not_found_count'],
              'registered_keys_in_service_count': keyStatus['registered_keys_count'],
              'registered_keys_in_service': keyStatus['registered_keys_in_service'],
              'not_found_keys': keyStatus['not_found_keys'],
              'found_keys': keyStatus['found_keys'],
            },
          })}',
          name: 'ShowcaseView',
        );
        OverlayManager.instance.update(show: false, scope: scope);
        return;
      }
      // If skippable, _skipInvalidShowcases should have already handled it
      // But if we're here, it means we couldn't skip further, so finish
      final keyStatus = _getKeyStatusSummary();
      // Get diagnostic info for current key
      final currentKeyDiagnostic = (keyStatus['key_diagnostics'] as List)
          .firstWhere(
            (d) => d['index'] == _activeWidgetId,
            orElse: () => {'key': currentKey.toString(), 'error': 'Diagnostic not found'},
          );
      developer.log(
        '${_getTimestamp()} 🏁 [SHOWCASE] _onStart - No controllers, skippable but can\'t skip further - FINISHING\n${_mapToString({
          'active_index': _activeWidgetId,
          'current_key': currentKey.toString(),
          'action': 'FINISH',
          'checking_scope': keyStatus['checking_scope'],
          'current_key_diagnostic': currentKeyDiagnostic,
          'key_status': {
            'total_keys': keyStatus['total_keys'],
            'found_count': keyStatus['found_count'],
            'not_found_count': keyStatus['not_found_count'],
            'registered_keys_in_service_count': keyStatus['registered_keys_count'],
            'registered_keys_in_service': keyStatus['registered_keys_in_service'],
            'not_found_keys': keyStatus['not_found_keys'],
            'found_keys': keyStatus['found_keys'],
          },
        })}',
        name: 'ShowcaseView',
      );
      _cleanupAfterSteps();
      OverlayManager.instance.update(show: false, scope: scope);
      onFinish?.call();
      return;
    }
    
    // Widget exists, start the showcase
    developer.log(
      '${_getTimestamp()} ✨ [SHOWCASE] _onStart - Starting tooltip display\n${_mapToString({
        'active_index': _activeWidgetId,
        'current_key': currentKey.toString(),
        'controller_count': controllers.length,
        'current_step_index': currentStepIndex,
        'total_steps': totalSteps,
        'step_display': '${(currentStepIndex ?? 0) + 1}/$totalSteps',
      })}',
      name: 'ShowcaseView',
    );
    
    onStart?.call(_activeWidgetId, currentKey);
    final controllerLength = controllers.length;
    for (var i = 0; i < controllerLength; i++) {
      final controller = controllers[i];
      final isAutoScroll =
          controller.config.enableAutoScroll ?? enableAutoScroll;
      if (controllerLength == 1 && isAutoScroll) {
        developer.log('${_getTimestamp()} 📜 [SHOWCASE] Scrolling into view', name: 'ShowcaseView');
        await controller.scrollIntoView();
      } else {
        controller.startShowcase();
      }
    }

    if (autoPlay) {
      _cancelTimer();
      // Showcase is first.
      final config = _getCurrentActiveControllers.firstOrNull?.config;
      final delay = config?.autoPlayDelay ?? autoPlayDelay;
      developer.log(
        '${_getTimestamp()} ⏱️ [SHOWCASE] Auto-play enabled, next in ${delay.inMilliseconds}ms',
        name: 'ShowcaseView',
      );
      _timer = Timer(
        delay,
            () => next(force: true),
      );
    }
  }

  /// Internal method to handle showcase completion.
  ///
  /// Runs reverse animations and triggers completion callbacks.
  Future<void> _onComplete() async {
    final currentControllers = _getCurrentActiveControllers;
    final controllerLength = currentControllers.length;
    
    final activeId = _activeWidgetId ?? -1;
    final currentKey = activeId >= 0 && activeId < (_ids?.length ?? 0) ? _ids![activeId] : null;

    developer.log(
      '${_getTimestamp()} ✅ [SHOWCASE] _onComplete - Completing step\n${_mapToString({
        'active_index': activeId,
        'current_key': currentKey?.toString(),
        'controller_count': controllerLength,
        'current_step_index': currentStepIndex,
        'total_steps': totalSteps,
        'step_display': currentStepIndex != null ? '${currentStepIndex! + 1}/$totalSteps' : 'N/A',
      })}',
      name: 'ShowcaseView',
    );

    await Future.wait([
      for (var i = 0; i < controllerLength; i++)
        if (!(currentControllers[i].config.disableScaleAnimation ??
            disableScaleAnimation) &&
            currentControllers[i].reverseAnimationCallback != null)
          currentControllers[i].reverseAnimationCallback!.call(),
    ]);

    if (activeId < (_ids?.length ?? activeId)) {
      onComplete?.call(activeId, _ids![activeId]);
    }

    if (autoPlay) _cancelTimer();
  }

  /// Cancels auto-play timer if active.
  void _cancelTimer() {
    if (!(_timer?.isActive ?? false)) return;
    _timer?.cancel();
    _timer = null;
  }

  /// Cleans up showcase state after completion.
  void _cleanupAfterSteps() {
    _ids = _activeWidgetId = null;
    _partitionKeys = null;
    _cancelTimer();
  }
}
