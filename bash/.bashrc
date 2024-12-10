# .bashrc

if [ -r /etc/bashrc ] && [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

for file in ~/.{path,exports,bash_prompt,functions,aliases,extra}; do
    [ -r "$file" ] && [ -f "$file" ] && source "$file";
done;
unset file;

shopt -s cdspell;
shopt -s checkwinsize;
shopt -s extglob
shopt -s globstar;
shopt -s histappend;
shopt -s nocaseglob;

eval "$(zoxide init bash --cmd cd)";
