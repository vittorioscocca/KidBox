import * as React from "react";

/**
 * Small red count badge overlaid on Home cards / tab items.
 */
export interface BadgeProps {
  /** Number to show. 0 / falsy renders nothing. */
  count?: number;
  /** Cap; above this shows `${max}+`. Default 99. */
  max?: number;
  tone?: "danger" | "orange" | "green" | "blue";
  style?: React.CSSProperties;
}

export function Badge(props: BadgeProps): JSX.Element | null;
