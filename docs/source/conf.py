# -*- coding: utf-8 -*-
import os
import sys
from datetime import date

from sphinx_scylladb_theme.utils import multiversion_regex_builder

sys.path.insert(0, os.path.abspath(".."))

# -- Global variables

# Build documentation for the following tags and branches
TAGS = []
BRANCHES = ['master', 'branch-3.4', 'branch-3.5', 'branch-3.6', 'branch-3.7', 'branch-3.8', 'branch-3.9', 'branch-3.10', 'branch-4.0', 'branch-4.1', 'branch-4.2', 'branch-4.3', 'branch-4.4', 'branch-4.5', 'branch-4.6', 'branch-4.7', 'branch-4.8', 'branch-4.9', 'branch-4.10', 'branch-4.11']
# Set the latest version.
LATEST_VERSION = 'branch-4.11'
# Set which versions are not released yet.
UNSTABLE_VERSIONS = ['master']
# Set which versions are deprecated
DEPRECATED_VERSIONS = []

# -- General configuration

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named 'sphinx.ext.*') or your custom
# ones.
extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.todo',
    'sphinx.ext.mathjax',
    'sphinx.ext.githubpages',
    'sphinx.ext.extlinks',
    'sphinx_sitemap',
    'sphinx_scylladb_theme',
    'sphinx_multiversion',  # optional
    'recommonmark',  # optional
]


# The suffix(es) of source filenames.
source_suffix = [".rst", ".md"]

# The master toctree document.
master_doc = 'index'

# General information about the project.
project = u'ScyllaDB Monitoring'
copyright = str(date.today().year) + ', ScyllaDB. All rights reserved.'
author = u'Scylla Project Contributors'

exclude_patterns = ['_build', '_utils', '**/common/*']

# The name of the Pygments (syntax highlighting) style to use.
pygments_style = 'sphinx'

current_version = "4.0.0"
res = ""
if os.path.isfile('../../CURRENT_VERSION.sh'):
    with open('../../CURRENT_VERSION.sh', 'r') as file:
        current_version = file.read().replace('\n', '')
current_branch = 'branch-' + '.'.join(current_version.split('.')[:2])

# Adds version variables for monitoring and manager versions when used in inline text
rst_prolog = """
.. |version| replace:: {current_version}
.. |branch_version| replace:: {current_branch}
.. |mon_root| replace::  `Scylla Monitoring Stack </>`__
""".format(current_version=current_version, current_branch=current_branch)

# -- Options for not found extension

# Template used to render the 404.html generated by this extension.
notfound_template =  '404.html'

# Prefix added to all the URLs generated in the 404 page.
notfound_urls_prefix = ''

# -- Options for multiversion

# Whitelist pattern for tags
smv_tag_whitelist = multiversion_regex_builder(TAGS)
# Whitelist pattern for branches
smv_branch_whitelist = multiversion_regex_builder(BRANCHES)
# Defines which version is considered to be the latest stable version.
smv_latest_version = LATEST_VERSION
# Defines the new name for the latest version.
smv_rename_latest_version = 'stable'
# Whitelist pattern for remotes (set to None to use local branches only)
smv_remote_whitelist = r'^origin$'
# Pattern for released versions
smv_released_pattern = r'^tags/.*$'
# Format for versioned output directories inside the build directory
smv_outputdir_format = '{ref.name}'

# -- Options for sitemap extension

sitemap_url_scheme = "/stable/{link}"

# -- Options for HTML output

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.
#
html_theme = 'sphinx_scylladb_theme'
html_static_path = ['_static']

# Theme options are theme-specific and customize the look and feel of a theme
# further.  For a list of options available for each theme, see the
# documentation.
html_theme_options = {
    'conf_py_path': 'docs/source/',
    'hide_version_dropdown': ['master'],
    'hide_edit_this_page_button': 'false',
    'hide_feedback_buttons': 'false',
    'github_issues_repository': 'scylladb/scylla-monitoring',
    'github_repository': 'scylladb/scylla-monitoring',
    'site_description': 'Scylla Monitoring Stack is a full stack for Scylla monitoring and alerting. The stack contains open source tools including Prometheus and Grafana, as well as custom Scylla dashboards and tooling.',
    'versions_unstable': UNSTABLE_VERSIONS,
    'versions_deprecated': DEPRECATED_VERSIONS,
    'zendesk_tag': 'pgbgkga1hpa6ug0732m8ae',
}

html_extra_path = ['robots.txt']

# If not None, a 'Last updated on:' timestamp is inserted at every page
# bottom, using the given strftime format.
# The empty string is equivalent to '%b %d, %Y'.
#
html_last_updated_fmt = '%d %B %Y'

# If true, SmartyPants will be used to convert quotes and dashes to
# typographically correct entities.
#
# html_use_smartypants = True

# Custom sidebar templates, maps document names to template names.
#
html_sidebars = {'**': ['side-nav.html']}

# Output file base name for HTML help builder.
htmlhelp_basename = 'ScyllaMonitorDocumentationdoc'

# URL which points to the root of the HTML documentation.
html_baseurl = 'https://monitoring.docs.scylladb.com'

# Dictionary of values to pass into the template engine’s context for all pages
html_context = {'html_baseurl': html_baseurl}
