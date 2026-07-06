import * as React from "react";

/**
 * Circular orange-gradient "Ask the AI" FAB with sparkles and a breathing pulse.
 */
export interface AskAIButtonProps {
  /** "fab" = 58px floating action button, "sm" = 42px inline. */
  size?: "fab" | "sm";
  /** Accessible label. */
  label?: string;
  /** Breathing pulse animation. Default true. */
  pulse?: boolean;
  onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void;
  style?: React.CSSProperties;
}

export function AskAIButton(props: AskAIButtonProps): JSX.Element;
