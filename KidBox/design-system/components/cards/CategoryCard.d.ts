import * as React from "react";

/**
 * Folder tile for Documents — neutral surface, folder icon, sync pill.
 */
export interface CategoryCardProps {
  title: string;
  /** Sub-hint line. Default "Apri categoria". */
  hint?: string;
  icon?: React.ReactNode;
  /** Sync pill label, e.g. "Sincronizzato"; omit to hide. */
  syncLabel?: string | null;
  syncTone?: "green" | "orange" | "red";
  onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void;
  style?: React.CSSProperties;
}

export function CategoryCard(props: CategoryCardProps): JSX.Element;
