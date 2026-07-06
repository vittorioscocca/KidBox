import * as React from "react";

/**
 * Family photo hero card with protection gradient + overlaid metadata.
 */
export interface HeroCardProps {
  title?: string;
  subtitle?: string;
  /** Small caption top-left (usually today's date). */
  dateText?: string;
  /** Pill top-right, e.g. "3 membri". */
  badgeText?: string;
  /** Background photo URL; omit for the warm gradient placeholder. */
  photo?: string | null;
  actionLabel?: string;
  height?: number;
  onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void;
  style?: React.CSSProperties;
}

export function HeroCard(props: HeroCardProps): JSX.Element;
