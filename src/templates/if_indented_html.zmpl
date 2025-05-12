@if ($.user.is_logged_in)
                <div class="d-none d-md-block ms-2 dropdown">
                    <button class="btn btn-outline-secondary btn-sm dropdown-toggle" type="button" id="userMenuDropdown" data-bs-toggle="dropdown" aria-expanded="false">
                        {{$.user.display_name}}
                    </button>
                    <ul class="dropdown-menu dropdown-menu-end" aria-labelledby="userMenuDropdown">
                        <li><a class="dropdown-item" href="/profile"><i class="bi bi-person me-2"></i>Profile</a></li>
                        <li><hr class="dropdown-divider"></li>
                        <li><a class="dropdown-item" href="/logout"><i class="bi bi-box-arrow-right me-2"></i>Log out</a></li>
                    </ul>
                </div>
@else
                <div class="d-none d-md-flex align-items-center ms-2">
                    <a href="/login" class="btn btn-outline-secondary btn-sm">Log in</a>
                    <a href="/register" class="btn btn-primary btn-sm ms-2">Sign up</a>
                </div>
@end
