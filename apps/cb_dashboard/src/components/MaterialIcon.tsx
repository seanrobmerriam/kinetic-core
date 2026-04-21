interface Props {
  name: string;
  className?: string;
}

export function MaterialIcon({ name, className = "" }: Props) {
  return (
    <span
      className={`${className} material-symbols-outlined`.trim()}
      aria-hidden="true"
    >
      {name}
    </span>
  );
}
