import * as React from "react";

/**
 * Rounded pill used for visibility tags, feature tags and filters.
 */
export interface ChipProps {
  children?: React.ReactNode;
  /** Category hex/token for the tinted variant, e.g. "var(--kb-cat-green)". */
  tint?: string | null;
  variant?: "neutral" | "tinted";
  icon?: React.ReactNode;
  style?: React.CSSProperties;
}

export function Chip(props: ChipProps): JSX.Element;
