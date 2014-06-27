# ri plugin for Vim

This plugin lets you search and navigate Ruby library and gem documentation inside
Vim.


![screenshot](https://github.com/danchoi/ri_vim/raw/master/screens/ri_vim5.png)

Advantages over the venerable `ri` command-line tool:

- write code and browse pertinent documentation in adjacent Vim windows
- search with autocompletion help
- hyperlinking lets you jump from definition to definition
- run back and forth through your jump history with CTRL-o and CTRL-i
- jump directly to gem READMEs and into the gem source directories
- directly open corresponding HTML-formatted rdoc documentation


## Prerequisites

- Ruby 1.9.2 or higher
- Vim 7.3 (will not work correctly on 7.2)
- rdoc 3.8 or higher


## Install

Copy the contents of plugin/ into your .vim/plugin directory.


## Commands

For the all the commands below, the mapleader is assumed to be `,`. If it is
`\` or something else for your setup, use that instead.


### Invoking the plugin

- `,r` opens the search/autocomplete window, and will use a horizontal split to
  display matching documentation
- `,R` opens the search/autocomplete window, and will use a vertical split to
  display matching documentatoin
- `,K` opens the search/autocomplete window and prefills it with the keyword
  under the cursor
- `K` is automatically remapped to use ri.vim if the current buffer is a \*.rb
  file

If these mapping clash or you don't like them, you can override some of them.
See **Changing keymappings** below.


### Using the search/autocomplete window

Withe the search/autocomplete window open, start typing the name of the class,
module, or method you want to lookup.

Press `TAB` to start autocompletion.

If you've started typing a name starting with a capital letter, you'll see
autocompletion suggestions for matching classes and modules. If you're looking
for a namespace-nested module or class, you can autocomplete the first
namespace, type `:` and then press `TAB` again to autocomplete the next inner
namespace.

![screenshot](https://github.com/danchoi/ri_vim/raw/master/screens/nested_search.png)

If you've started typing a name starting with a lower case letter or
a symbol that is valid in Ruby method names (i.e., `/^[=*\/&|%^\[<>]/`), ri.vim
will suggest matching methods from different classes and modules.

![screenshot](https://github.com/danchoi/ri_vim/raw/master/screens/method_search.png)

Use the standard Vim autocompletion commands to move up and down the match
list.

- `CTRL-p` and `CTRL-n` let you navigate the drop-down matches. Press `ENTER` to select
one.
- `CTRL-e` closes the match list and lets you continue typing
- `CTRL-u`: when the match list is active, cycles forward through the match
  list and what you've typed so far; when the match list is inactive, erases
  what you've typed.
- both `TAB` and `CTRL-x CTRL-u` reactivates autocompletion if it's gone away
- `CTRL-y` selects the highlighted match without triggering ENTER

When you're searching for a class or module (but not yet for method searches),
you will sometimes see a little number in parentheses to the right of a match.
This is a rough indicator of how much actual documentation there is to see for
that class or module. It actually represents how many "parts" of the generated
documentation has a "comment" associated with it. (Don't ask me what the
definition of a "part" is; it's just something the RDoc::RI codebase knows
about.) Please note that the relationship between the number of comment-parts
and the length of the documentation is not exactly linear. But it's still a
useful filter for knowing which documentation pages are worth looking up.


### The documentation window

* `,,r` invokes the class/module method autocompletion window
* `-` goes up from a method page to the page of the parent class or module
* `CTRL-o` and `CTRL-i` jump you back and forward through the documentation pages you've visited

When you find a matching method or class or module and press `ENTER`, you
should see the ri documentation, with a light touch of color-highlighting,
display in a Vim window.

![screenshot](https://github.com/danchoi/ri_vim/raw/master/screens/ri_doc.png)

You can move to cursor to any valid Ruby method or class/module name on this
page (including the class and instance methods at the bottom) and press `ENTER`
to jump to the documentation.

You can also find a method on any class or module you're looking at the
documentation for by pressing `,,r`. This brings up the class/module method
autocompletion window:

![screenshot](https://github.com/danchoi/ri_vim/raw/master/screens/class_method_autocomplete.png)

Here you can just start typing the method name (you don't need to indicate
whether it is a class or instance method) and press `TAB`. Then the match list
should narrow down your choices quickly. Again, the numbers here are a very rough
indicator of how much documentation there is to see for that method.

Let's look at `#encode`:

![screenshot](https://github.com/danchoi/ri_vim/raw/master/screens/class_instance_method.png)

When you are looking at the documentation for an instance or class method, you
can still use `,,r` to browse and jump to other methods on that same class or
module.

You can also use `-` to jump up the hierarchy to the page for the `String`
class. If you were in a nested class, e.g. `File::Stat`, you could also jump up
to `File` with `-`.

Alternatively, you can use the standard Vim command `CTRL-o` to jump back to
where you were before you jumped to this page. `CTRL-i` takes you back forward.


### Gem READMEs and HTML RDocs

* `,g` takes you to the README of the gem, if you're looking at documentation
  for a gem
* `,h` opens the HTML RDoc version of the gem documentation you are looking at

If you are looking at documentation for a Gem, you can see the README for
that gem (assuming it exists and is called README.\*) by pressing `,g`.

If you've generated the HTML RDoc documentation for this Gem, you can open it
in a web browser by pressing `,h`.

If you're looking at a gem's README, you can change the local working directory
to the gem root directory by using the vim command `:lcd %:h`.


## How to generate ri documentation

`ri.vim` won't work very well unless you have generated ri documentation for
your Ruby built-in library, standard library, and your installed Ruby gems.

Please consult other reference sources for instructions specific to your
particular setup.

I'll try to cover some common cases:

If you use RVM, run this to install ri documentation for the built-in and
standard library of your active Ruby installation:

    rvm docs generate-ri

You can check if this worked by running a command like `ri Enumerable` or `ri
IO` on the command line.

To generate ri documentation for your gems, use these commands:

    # for global gems
    gem list | tr -d '(,)' | awk '{print $1, "--version", $2}' | xargs -n3 gem rdoc --ri --no-rdoc

    # for bundled gems
    bundle list | tr -d '*(,)' | awk '{print $1, "--version", $2}' | xargs -n3 gem rdoc --ri --no-rdoc

If you like using `ri.vim`, you may want to make to remove `--no-ri` if you
added that to your `.gemrc`. This will make sure that the `gem install` command
automatically generates ri documentation.


## Changing keymappings

You can change the keymappings for invoking ri.vim by appending something like
this to your `.vimrc`:

    nnoremap  ,ri :call ri#OpenSearchPrompt(0)<cr> " horizontal split
    nnoremap  ,RI :call ri#OpenSearchPrompt(1)<cr> " vertical split
    nnoremap  ,RK :call ri#LookupNameUnderCursor()<cr> " keyword lookup


## Maintainers

- Matthias Günther [wikimatze](https://github.com/wikimatze)
- Daniel Choi [danchoi](https://github.com/danchoi)


## Acknowledgements

Thanks to Eric Hodel for developing the ri and rdoc infrastructure that ri.vim
builds on. ri.vim adds just a little piece to that very useful codebase.

Thank you to [Suraj Kurapati](https://github.com/sunaku) for the tip on
how to generate ri documention for installed gems.


## Bug reports and feature requests

Please submit them here:

- <https://github.com/danchoi/ri.vim/issues>


## About the developer

My name is Daniel Choi. I specialize in Ruby, Rails, MySQL, PostgreSQL, and iOS
development. I am based in Cambridge, Massachusetts, USA.

- Twitter: [@danchoi](http://twitter.com/#!/danchoi)
- Personal Email: dhchoi@gmail.com
- My Homepage: <http://danielchoi.com/software>

