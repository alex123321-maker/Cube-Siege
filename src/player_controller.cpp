#include "player_controller.h"

#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/variant/plane.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

PlayerController::PlayerController() {
}

PlayerController::~PlayerController() {
}

void PlayerController::_bind_methods() {
    // Properties
    ClassDB::bind_method(D_METHOD("set_speed", "speed"), &PlayerController::set_speed);
    ClassDB::bind_method(D_METHOD("get_speed"), &PlayerController::get_speed);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "speed"), "set_speed", "get_speed");

    ClassDB::bind_method(D_METHOD("set_dash_speed", "dash_speed"), &PlayerController::set_dash_speed);
    ClassDB::bind_method(D_METHOD("get_dash_speed"), &PlayerController::get_dash_speed);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "dash_speed"), "set_dash_speed", "get_dash_speed");

    ClassDB::bind_method(D_METHOD("set_max_health", "max_health"), &PlayerController::set_max_health);
    ClassDB::bind_method(D_METHOD("get_max_health"), &PlayerController::get_max_health);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_health"), "set_max_health", "get_max_health");

    ClassDB::bind_method(D_METHOD("get_current_health"), &PlayerController::get_current_health);
    ClassDB::bind_method(D_METHOD("get_is_dashing"), &PlayerController::get_is_dashing);
    ClassDB::bind_method(D_METHOD("get_is_parrying"), &PlayerController::get_is_parrying);

    // Combat & Actions
    ClassDB::bind_method(D_METHOD("perform_dash"), &PlayerController::perform_dash);
    ClassDB::bind_method(D_METHOD("perform_parry"), &PlayerController::perform_parry);
    ClassDB::bind_method(D_METHOD("take_damage", "damage"), &PlayerController::take_damage);

    // Signals
    ADD_SIGNAL(MethodInfo("health_changed", PropertyInfo(Variant::FLOAT, "current_health"), PropertyInfo(Variant::FLOAT, "max_health")));
    ADD_SIGNAL(MethodInfo("dash_performed"));
    ADD_SIGNAL(MethodInfo("parry_triggered", PropertyInfo(Variant::BOOL, "successful")));
    ADD_SIGNAL(MethodInfo("player_died"));
}

void PlayerController::_ready() {
    current_health = max_health;
}

void PlayerController::_physics_process(double delta) {
    // Timers update
    if (dash_cooldown_timer > 0.0f) {
        dash_cooldown_timer -= static_cast<float>(delta);
    }
    if (parry_cooldown_timer > 0.0f) {
        parry_cooldown_timer -= static_cast<float>(delta);
    }

    if (is_dashing) {
        dash_timer -= static_cast<float>(delta);
        if (dash_timer <= 0.0f) {
            is_dashing = false;
        }
    }

    if (is_parrying) {
        parry_timer -= static_cast<float>(delta);
        if (parry_timer <= 0.0f) {
            is_parrying = false;
        }
    }

    Input *input = Input::get_singleton();
    if (input) {
        if (input->is_action_just_pressed("dash")) {
            perform_dash();
        }
        if (input->is_action_just_pressed("class_utility")) {
            perform_parry();
        }
    }

    handle_movement(delta);
    handle_aim();
}

void PlayerController::handle_movement(double delta) {
    Input *input = Input::get_singleton();
    if (!input) return;

    Vector3 velocity = get_velocity();

    if (is_dashing) {
        velocity.x = dash_direction.x * dash_speed;
        velocity.z = dash_direction.z * dash_speed;
        velocity.y = 0.0f;
    } else {
        Vector2 input_dir = input->get_vector("move_left", "move_right", "move_up", "move_down");
        Vector3 direction = Vector3(input_dir.x, 0.0f, input_dir.y);

        if (direction.length_squared() > 0.001f) {
            direction.normalize();
            velocity.x = direction.x * speed;
            velocity.z = direction.z * speed;
        } else {
            velocity.x = Math::move_toward(velocity.x, 0.0f, speed);
            velocity.z = Math::move_toward(velocity.z, 0.0f, speed);
        }
        velocity.y = 0.0f;
    }

    set_velocity(velocity);
    move_and_slide();
}

void PlayerController::handle_aim() {
    Viewport *vp = get_viewport();
    if (!vp) return;

    Camera3D *cam = vp->get_camera_3d();
    if (!cam) return;

    Vector2 mouse_pos = vp->get_mouse_position();
    Vector3 ray_origin = cam->project_ray_origin(mouse_pos);
    Vector3 ray_normal = cam->project_ray_normal(mouse_pos);

    Vector3 player_pos = get_global_position();
    Plane ground_plane(Vector3(0, 1, 0), player_pos.y);

    Vector3 target_point;
    if (ground_plane.intersects_ray(ray_origin, ray_normal, &target_point)) {
        Vector3 aim_dir = (target_point - player_pos);
        aim_dir.y = 0.0f;

        if (aim_dir.length_squared() > 0.01f) {
            aim_dir.normalize();
            look_at(player_pos + aim_dir, Vector3(0, 1, 0));
        }
    }
}

void PlayerController::perform_dash() {
    if (dash_cooldown_timer > 0.0f || is_dashing) {
        return;
    }

    Input *input = Input::get_singleton();
    Vector2 input_dir = input ? input->get_vector("move_left", "move_right", "move_up", "move_down") : Vector2();

    if (input_dir.length_squared() > 0.001f) {
        dash_direction = Vector3(input_dir.x, 0.0f, input_dir.y).normalized();
    } else {
        // Dash forward in looking direction if stationary
        dash_direction = -get_global_transform().basis.get_column(2);
        dash_direction.y = 0.0f;
        dash_direction.normalize();
    }

    is_dashing = true;
    dash_timer = dash_duration;
    dash_cooldown_timer = dash_cooldown;

    emit_signal("dash_performed");
}

void PlayerController::perform_parry() {
    if (parry_cooldown_timer > 0.0f || is_parrying) {
        return;
    }

    is_parrying = true;
    parry_timer = 0.5f;
    parry_cooldown_timer = 5.0f; // Base cooldown

    emit_signal("parry_triggered", false);
}

void PlayerController::take_damage(float damage) {
    if (is_dashing) {
        // Invulnerability window during dash
        return;
    }

    if (is_parrying) {
        // Successful parry! Block 100% damage
        is_parrying = false;
        parry_cooldown_timer = 3.0f; // Reduced cooldown on successful parry
        emit_signal("parry_triggered", true);
        return;
    }

    current_health -= damage;
    emit_signal("health_changed", current_health, max_health);

    if (current_health <= 0.0f) {
        current_health = 0.0f;
        emit_signal("player_died");
    }
}

void PlayerController::set_speed(float p_speed) { speed = p_speed; }
float PlayerController::get_speed() const { return speed; }

void PlayerController::set_dash_speed(float p_dash_speed) { dash_speed = p_dash_speed; }
float PlayerController::get_dash_speed() const { return dash_speed; }

void PlayerController::set_max_health(float p_max_health) { max_health = p_max_health; }
float PlayerController::get_max_health() const { return max_health; }

float PlayerController::get_current_health() const { return current_health; }
bool PlayerController::get_is_dashing() const { return is_dashing; }
bool PlayerController::get_is_parrying() const { return is_parrying; }
