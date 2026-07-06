import * as React from "react";

/**
 * Circular avatar with hairline ring; initials or person fallback.
 */
export interface AvatarProps {
  src?: string | null;
  /** Used for initials fallback + alt text. */
  name?: string;
  /** Diameter in px. Default 40. */
  size?: number;
  style?: React.CSSProperties;
}

export function Avatar(props: AvatarProps): JSX.Element;
