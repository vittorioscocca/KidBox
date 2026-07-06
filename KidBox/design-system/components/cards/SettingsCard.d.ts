import * as React from "react";

/**
 * Settings list-row card: leading tinted icon, title + subtitle, optional
 * trailing control and expandable extra content.
 */
export interface SettingsCardProps {
  title: string;
  subtitle?: string;
  icon?: React.ReactNode;
  tone?: "primary" | "secondary" | "info" | "warning" | "danger";
  /** Trailing node (chevron, toggle, edit button). */
  trailing?: React.ReactNode;
  onClick?: (e: React.MouseEvent) => void;
  /** Extra content rendered inside the same visual group. */
  children?: React.ReactNode;
  style?: React.CSSProperties;
}

export function SettingsCard(props: SettingsCardProps): JSX.Element;
