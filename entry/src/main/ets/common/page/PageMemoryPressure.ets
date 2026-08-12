import { AbilityConstant } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';

/** 内存压力严重度（由 MemoryLevel 归并，再按 performanceClass 调参） */
export enum MemoryPressureSeverity {
  NONE = 0,
  MILD = 1,
  HARD = 2,
  EMERGENCY = 3
}

/** 单次内存压力下的页面淘汰 / 预取 / Worker 并发策略 */
export interface MemoryPressurePolicy {
  severity: MemoryPressureSeverity;
  previewBudgetMultiplier: number;
  /** 预取半径倍率（相对调用方传入的 prefetchRange） */
  prefetchRangeMultiplier: number;
  /** 为 true 时仅对显示页/中心拉预览档，远页跳过预览预取 */
  skipDistantPreviewPrefetch: boolean;
  /** 非显示页：丢掉阅读档及以上 */
  evictOffscreenHighRes: boolean;
  /** 非显示页：丢掉全部光栅 */
  evictOffscreenAll: boolean;
  /** 显示页：丢掉阅读档（保留预览） */
  evictDisplayedHighRes: boolean;
  /** 取消 Worker 队列中的待光栅任务 */
  cancelWorkerQueue: boolean;
  /** Worker 池最大同时忙碌数（不销毁池） */
  maxActiveWorkers: number;
}

/**
 * API 24 MemoryLevel 数值（避免在 compatibleSdk 22 上直接引用新枚举触发 SysCap 告警）。
 * UI_HIDDEN=3, BACKGROUND_MODERATE=4, BACKGROUND_LOW=5, BACKGROUND_CRITICAL=6
 */
const MEMORY_LEVEL_UI_HIDDEN_VALUE: number = 3;
const MEMORY_LEVEL_BACKGROUND_MODERATE_VALUE: number = 4;
const MEMORY_LEVEL_BACKGROUND_LOW_VALUE: number = 5;
const MEMORY_LEVEL_BACKGROUND_CRITICAL_VALUE: number = 6;

/**
 * 将系统 MemoryLevel（含 API 24 后台档）归并为严重度。
 */
export function classifyMemoryPressureSeverity(level: AbilityConstant.MemoryLevel): MemoryPressureSeverity {
  if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_MODERATE) {
    return MemoryPressureSeverity.NONE;
  }
  if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_LOW) {
    return MemoryPressureSeverity.MILD;
  }
  if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL) {
    return MemoryPressureSeverity.HARD;
  }
  // API 24+ 后台档：用数值比较，兼容 compileSdk 高于 compatibleSdk 的告警规避
  const levelValue: number = Number(level);
  if (levelValue === MEMORY_LEVEL_UI_HIDDEN_VALUE ||
    levelValue === MEMORY_LEVEL_BACKGROUND_MODERATE_VALUE) {
    return MemoryPressureSeverity.HARD;
  }
  if (levelValue === MEMORY_LEVEL_BACKGROUND_LOW_VALUE ||
    levelValue === MEMORY_LEVEL_BACKGROUND_CRITICAL_VALUE) {
    return MemoryPressureSeverity.EMERGENCY;
  }
  return MemoryPressureSeverity.MILD;
}

/**
 * 按严重度 + deviceInfo.performanceClass 生成淘汰策略。
 */
export function resolveMemoryPressurePolicy(level: AbilityConstant.MemoryLevel): MemoryPressurePolicy {
  const severity = classifyMemoryPressureSeverity(level);
  const perf = deviceInfo.performanceClass;
  const isLowPerf = perf === deviceInfo.PerformanceClassLevel.CLASS_LEVEL_LOW;
  const isHighPerf = perf === deviceInfo.PerformanceClassLevel.CLASS_LEVEL_HIGH;

  if (severity === MemoryPressureSeverity.NONE) {
    const nonePolicy: MemoryPressurePolicy = {
      severity: severity,
      previewBudgetMultiplier: 1.0,
      prefetchRangeMultiplier: 1.0,
      skipDistantPreviewPrefetch: false,
      evictOffscreenHighRes: false,
      evictOffscreenAll: false,
      evictDisplayedHighRes: false,
      cancelWorkerQueue: false,
      maxActiveWorkers: 64
    };
    return nonePolicy;
  }

  if (severity === MemoryPressureSeverity.MILD) {
    const mildPolicy: MemoryPressurePolicy = {
      severity: severity,
      previewBudgetMultiplier: isLowPerf ? 0.4 : (isHighPerf ? 0.7 : 0.55),
      prefetchRangeMultiplier: isLowPerf ? 0.4 : (isHighPerf ? 0.75 : 0.55),
      skipDistantPreviewPrefetch: isLowPerf,
      evictOffscreenHighRes: true,
      evictOffscreenAll: false,
      evictDisplayedHighRes: false,
      cancelWorkerQueue: true,
      maxActiveWorkers: isLowPerf ? 1 : (isHighPerf ? 3 : 2)
    };
    return mildPolicy;
  }

  if (severity === MemoryPressureSeverity.HARD) {
    const hardPolicy: MemoryPressurePolicy = {
      severity: severity,
      previewBudgetMultiplier: isLowPerf ? 0.25 : (isHighPerf ? 0.45 : 0.35),
      prefetchRangeMultiplier: isLowPerf ? 0.25 : (isHighPerf ? 0.5 : 0.35),
      skipDistantPreviewPrefetch: true,
      evictOffscreenHighRes: true,
      evictOffscreenAll: true,
      evictDisplayedHighRes: true,
      cancelWorkerQueue: true,
      maxActiveWorkers: isHighPerf ? 2 : 1
    };
    return hardPolicy;
  }

  // EMERGENCY：后台濒危，尽量只留显示页预览
  const emergencyPolicy: MemoryPressurePolicy = {
    severity: severity,
    previewBudgetMultiplier: 0.15,
    prefetchRangeMultiplier: 0.2,
    skipDistantPreviewPrefetch: true,
    evictOffscreenHighRes: true,
    evictOffscreenAll: true,
    evictDisplayedHighRes: true,
    cancelWorkerQueue: true,
    maxActiveWorkers: 1
  };
  return emergencyPolicy;
}
