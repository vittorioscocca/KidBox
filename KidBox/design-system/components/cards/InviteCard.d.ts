import * as React from "react";

/**
 * "Invita l'altro genitore" prompt card — leading icon, copy, trailing chevron.
 */
export interface InviteCardProps {
  title?: string;
  subtitle?: string;
  icon?: React.ReactNode;
  onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void;
  style?: React.CSSProperties;
}

export function InviteCard(props: InviteCardProps): JSX.Element;
