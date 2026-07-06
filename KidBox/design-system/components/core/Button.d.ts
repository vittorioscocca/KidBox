import * as React from "react";

/**
 * KidBox primary button. Ink-filled by default (mirrors LoginView); use `ai`
 * for the orange-gradient AI call-to-action.
 */
export interface ButtonProps {
  children?: React.ReactNode;
  /** Visual style. */
  variant?: "primary" | "accent" | "ai" | "secondary" | "ghost" | "danger";
  size?: "sm" | "md" | "lg";
  /** Leading icon node (pass a Lucide/SF-style glyph). */
  icon?: React.ReactNode;
  /** Trailing icon node. */
  iconRight?: React.ReactNode;
  fullWidth?: boolean;
  disabled?: boolean;
  onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void;
  type?: "button" | "submit" | "reset";
  style?: React.CSSProperties;
}

export function Button(props: ButtonProps): JSX.Element;
